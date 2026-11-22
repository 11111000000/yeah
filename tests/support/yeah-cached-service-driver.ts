/**
 * Драйвер проверки: мёртвый сервис в кэше плагина не выдаёт себя за живой.
 *
 * Живой прогон 2026-11-22 (21:00-21:48 UTC) наткнулся на это: ядро сервиса
 * умерло, а ссылка на него в плагине осталась, и каждый следующий агент
 * приходил к сокету, за которым нет ядра.  Оркестратор писал об этом
 * «ACP connection closed» — 32 раза за час, пока плагин не перезагрузили
 * вручную.
 *
 * Проверка волны 74 (`yeah-dead-socket-driver.ts`) закрывает другой случай:
 * файл сокета остался от мёртвого процесса, и сервис поднимается заново.
 * Здесь другой случай — сервис УЖЕ был поднят, ссылка на него лежит в кэше
 * плагина, и ядро умерло.  Кэш — это ссылка, а не доказательство жизни.
 *
 * Драйвер поднимает настоящее ядро через собственный код плагина
 * (`ensureService`), убивает его на живом месте и просит у плагина соединение
 * с ТЕМ ЖЕ сервисом из кэша.  Плагин должен спросить сокет, жив ли сервис,
 * и поднять новый, если нет.  Следующий агент должен получить ответ.
 *
 * Модель — подделка: ход заканчивается инструментом `finish`, и ни сети, ни
 * ключа не нужно.
 */
import { existsSync } from "node:fs";
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
 * Клиент ACP поверх потока плагина: рукопожатие, сессия и один ход.
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

  /** Закрывает соединение агента. */
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

/** Ждать выхода процесса сервиса. */
function waitExit(child: { once(event: string, listener: () => void): void }): Promise<void> {
  return new Promise<void>((resolve) => {
    child.once("exit", () => resolve());
  });
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
  const command: [string, ...string[]] = [emacs, "-Q", "--batch", "--eval", serviceForm(lib)];
  const first = await ensureService({ name, command, env, timeoutMs: 30_000 });
  if (!first.process) {
    throw new Error("плагин не поднял ядро: сервис нашёлся сам, а поднимать было некому");
  }

  // Ядро умирает на живом месте: файл сокета остаётся, слушать его некому.
  const died = waitExit(first.process);
  first.process.kill("SIGKILL");
  await died;
  if (!existsSync(first.socketPath)) {
    throw new Error("ядро умерло, а сокета не осталось: проверка проверяет не то");
  }

  // Следующий агент: у плагина в кэше лежит ССЫЛКА на мёртвый сервис.
  const transport = await yeahTransport({
    launch,
    key: "",
    mode: "service",
    serviceName: name,
    // Поднятое ядро — то же, что и в прошлый раз: та же форма, тот же
    // поддельный ход.  Команда сервиса приходит из плагина, и без неё он
    // поднял бы второе ядро своей формы — с gptel, которого тут нет.
    serviceCommand: command,
    service: first,
  });
  const agent = new Agent(transport.stream);
  try {
    if (!transport.service?.process) {
      throw new Error("плагин поверил мёртвому сервису из кэша: новый не поднят");
    }
    const init = await agent.request("initialize", {
      protocolVersion: 1,
      clientCapabilities: {},
    });
    if (!init.result) {
      throw new Error(`ядро не ответило на рукопожатие: ${JSON.stringify(init.error ?? null)}`);
    }
    const session = await agent.request("session/new", { cwd: workspace ?? lib });
    const sessionId = session.result?.sessionId;
    if (typeof sessionId !== "string") {
      throw new Error(`ядро не открыло сессию: ${JSON.stringify(session.error ?? null)}`);
    }
    const prompt = await agent.request("session/prompt", {
      sessionId,
      prompt: [{ type: "text", text: "сделай дело" }],
    });
    if (prompt.result?.stopReason !== "end_turn") {
      throw new Error(
        `ядро закончило ход с ${JSON.stringify(prompt.result?.stopReason ?? null)}: ${JSON.stringify(prompt.error ?? null)}`,
      );
    }

    process.stdout.write(
      `${JSON.stringify({
        ok: true,
        socket: transport.service.socketPath,
        cachedServiceReplaced: true,
        answered: true,
      })}\n`,
    );
  } finally {
    await agent.close();
    await transport.service.close();
  }
}

main().catch((error: unknown) => {
  process.stderr.write(
    `мёртвый-сервис-проверка: ${error instanceof Error ? error.message : String(error)}\n`,
  );
  process.exit(1);
});
