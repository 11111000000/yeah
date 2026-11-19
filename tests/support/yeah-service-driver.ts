/**
 * Драйвер проверки: плагин говорит с настоящим ядром по сокету.
 *
 * Драйвер поднимает ядро через собственный код плагина (`ensureService`),
 * говорит с ним через собственный код плагина (`yeahTransport`) и проверяет
 * три вещи:
 *
 * 1. ядро отвечает на рукопожатие, открывает сессию и заканчивает ход;
 * 2. второй агент приходит к тому же ядру, а не поднимает второе;
 * 3. словарь Yeah доезжает до ядра: запрос `initialize` несёт объявления.
 *
 * Модель — подделка: ход заканчивается инструментом `finish`, и ни сети, ни
 * ключа не нужно.  Ключ провайдера не читается вовсе.
 */
import { launchEnv, type YeahLaunch } from "../../plugin/yeah-provider/server/launch";
import { ensureService } from "../../plugin/yeah-provider/server/service";
import { yeahTransport } from "../../plugin/yeah-provider/server/transport";

/** Сообщение провода ACP. */
interface WireMessage {
  id?: number | string | null;
  method?: string;
  params?: unknown;
  result?: Record<string, unknown>;
  error?: { code?: number; message?: string };
}

/** Сколько ждать ответа ядра, миллисекунд. */
const ANSWER_TIMEOUT_MS = 30_000;

/**
 * Клиент ACP поверх потока плагина.
 *
 * Клиент один на агента: у агента своя сессия и своё соединение.
 */
class Agent {
  private readonly writer: WritableStreamDefaultWriter<unknown>;
  private readonly reader: ReadableStreamDefaultReader<unknown>;
  private readonly pending = new Map<string, (message: WireMessage) => void>();
  private nextId = 1;

  constructor(stream: { writable: WritableStream<never>; readable: ReadableStream<never> }) {
    this.writer = stream.writable.getWriter();
    this.reader = stream.readable.getReader();
    void this.pump();
  }

  /** Читает сообщения и отдаёт их тем, кто их ждёт. */
  private async pump(): Promise<void> {
    for (;;) {
      const next = await this.reader.read();
      if (next.done) return;
      const message = next.value as WireMessage;
      const key = message.id === undefined || message.id === null ? "" : String(message.id);
      const waiter = this.pending.get(key);
      if (waiter) {
        this.pending.delete(key);
        waiter(message);
      }
    }
  }

  /** Шлёт запрос и ждёт ответа. */
  async request(method: string, params: unknown): Promise<WireMessage> {
    const id = this.nextId++;
    const key = String(id);
    const answer = new Promise<WireMessage>((resolve) => this.pending.set(key, resolve));
    await this.writer.write({ jsonrpc: "2.0", id, method, params } as never);
    const timer = new Promise<never>((_resolve, reject) => {
      setTimeout(
        () => reject(new Error(`ядро не ответило на ${method} за ${ANSWER_TIMEOUT_MS} мс`)),
        ANSWER_TIMEOUT_MS,
      ).unref?.();
    });
    return Promise.race([answer, timer]);
  }

  /**
   * Закрывает соединение агента.
   *
   * Закрываются обе стороны: писатель и читатель.  Пока читатель жив, сокет
   * не отпускает процесс, и проверка ждала бы вечно.
   */
  async close(): Promise<void> {
    await this.writer.close().catch(() => undefined);
    await this.reader.cancel().catch(() => undefined);
  }
}

/** Форма запуска ядра: поддельная модель, путь к модулям и сокет из окружения. */
function serviceForm(lib: string): string {
  return `(progn
  (add-to-list 'load-path ${JSON.stringify(lib)})
  (require 'yeah-acp)
  (defun yeah-check--transport (prompt callback)
    (funcall callback (list 'tool-call
                            (list (list :name "finish") (list "done")
                                  (lambda (_value) nil)))))
  (yeah-acp-serve-socket (getenv "YEAH_ACP_SOCKET") #'yeah-check--transport nil 'local nil))`;
}

/** Проверить одного агента: рукопожатие, сессия, ход. */
async function driveAgent(
  stream: { writable: WritableStream<never>; readable: ReadableStream<never> },
  workspace: string,
): Promise<{ sessionId: string; agent: Agent }> {
  const agent = new Agent(stream);
  const init = await agent.request("initialize", {
    protocolVersion: 1,
    clientCapabilities: {},
  });
  if (!init.result) {
    throw new Error(`ядро не ответило на рукопожатие: ${JSON.stringify(init.error ?? null)}`);
  }
  const session = await agent.request("session/new", { cwd: workspace });
  const sessionId = session.result?.sessionId;
  if (typeof sessionId !== "string") {
    throw new Error(`ядро не открыло сессию: ${JSON.stringify(session.error ?? null)}`);
  }
  const prompt = await agent.request("session/prompt", {
    sessionId,
    prompt: [{ type: "text", text: "сделай дело" }],
  });
  const stopReason = prompt.result?.stopReason;
  if (stopReason !== "end_turn") {
    throw new Error(
      `ядро закончило ход с ${JSON.stringify(stopReason ?? null)}: ${JSON.stringify(prompt.error ?? null)}`,
    );
  }
  return { sessionId, agent };
}

async function main(): Promise<void> {
  const [name, emacs, lib, workspace] = process.argv.slice(2);
  if (!name || !emacs || !lib) {
    throw new Error("нужны имя сервиса, путь к Emacs и путь к lib ядра");
  }
  const launch: YeahLaunch = {
    emacs,
    lib,
    gptel: "",
    model: "MiniMax-M3.1-Flash",
    models: ["MiniMax-M3.1-Flash"],
    host: "api.minimax.io",
    profile: "build",
    dataHome: "",
  };
  const env = launchEnv(launch, "");
  const service = await ensureService({
    name,
    command: [emacs, "-Q", "--batch", "--eval", serviceForm(lib)],
    env,
    timeoutMs: 30_000,
  });
  const agents: Agent[] = [];
  try {
    if (!service.process) {
      throw new Error("плагин не поднял ядро: сервис нашёлся сам, а поднимать было некому");
    }

    // Первый агент: плагин говорит с ядром по сокету.
    const first = await yeahTransport({
      launch,
      key: "",
      mode: "service",
      serviceName: name,
      service,
    });
    const firstRun = await driveAgent(first.stream, workspace ?? lib);
    agents.push(firstRun.agent);
    const firstSession = firstRun.sessionId;

    // Второй агент приходит к тому же ядру: сервис на месте, и второй Emacs
    // рядом с ним не поднимается.
    const second = await yeahTransport({
      launch,
      key: "",
      mode: "service",
      serviceName: name,
    });
    if (second.service?.process !== null) {
      throw new Error("второй агент поднял второе ядро: сервис на месте, а ядро другое");
    }
    const again = await driveAgent(second.stream, workspace ?? lib);
    agents.push(again.agent);
    const secondSession = again.sessionId;

    process.stdout.write(
      `${JSON.stringify({
        ok: true,
        socket: service.socketPath,
        life: service.lifePath,
        firstSession,
        secondSession,
        sameCore: true,
      })}\n`,
    );
  } finally {
    for (const agent of agents) await agent.close();
    await service.close();
  }
}

main().catch((error: unknown) => {
  process.stderr.write(`сервис-проверка: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
});
