/**
 * Драйвер проверки: плагин направляет уточнение в ход настоящего ядра.
 *
 * Драйвер поднимает настоящее ядро через собственный код плагина
 * (`ensureService'), говорит с ним через собственный код плагина
 * (`yeahTransport', `yeahSteerWire', `yeahSteerConnection') и проверяет, что
 * запрос оркестратора со `delivery: "steer"' доехал до ядра как `session/steer'
 * и не обернулся в новый ход.
 *
 * Ядро — настоящее, модель — подделка: ход не кончается, потому что transport
 * не отвечает.  Ход, который идёт, и есть условие steering'а: уточнение
 * приходит посреди хода, и ядро кладёт его в очередь хода.
 *
 * Ключ провайдера не читается вовсе.
 */
import { launchEnv, type YeahLaunch } from "../../plugin/yeah-provider/server/launch";
import { ensureService } from "../../plugin/yeah-provider/server/service";
import {
  STEER_CAPABILITY,
  yeahSteerConnection,
  yeahSteerRegistry,
  yeahSteerWire,
} from "../../plugin/yeah-provider/server/steer";
import { yeahTransport } from "../../plugin/yeah-provider/server/transport";

/** Сообщение провода ACP. */
interface WireMessage {
  id?: number | string | null;
  method?: string;
  params?: unknown;
  result?: unknown;
  error?: { code?: number; message?: string };
}

/** Событие провайдера: то, что плагин отдаёт оркестратору. */
interface ProviderEvent {
  type: string;
  sessionId?: string;
  clientMessageId?: string;
  turnId?: string;
  state?: string;
  capabilities?: string[];
  result?: { type?: string; turnId?: string; error?: { message?: string } };
}

/** Ввод провайдера: то, что оркестратор отдаёт плагину. */
interface ProviderInput {
  type: string;
  requestId?: string;
  sessionId?: string;
  prompt?: { clientMessageId: string; delivery: string };
  config?: {
    cwd: string;
    providerOptions?: Record<string, unknown>;
  };
}

/**
 * Записать провод и пропустить его дальше.
 *
 * Запись нужна проверке: она видит всё, что дошло до ядра, включая
 * `session/steer' плагина и `session/cancel', которого быть не должно.
 */
function recordStream(stream: {
  writable: WritableStream<WireMessage>;
  readable: ReadableStream<WireMessage>;
}): { writable: WritableStream<WireMessage>; readable: ReadableStream<WireMessage>; log: WireMessage[] } {
  const log: WireMessage[] = [];
  const writer = stream.writable.getWriter();
  const reader = stream.readable.getReader();
  return {
    log,
    writable: new WritableStream<WireMessage>({
      async write(message) {
        log.push(message);
        await writer.write(message);
      },
      async close() {
        await writer.close().catch(() => undefined);
      },
      async abort(reason) {
        await writer.abort(reason).catch(() => undefined);
      },
    }),
    readable: new ReadableStream<WireMessage>({
      async pull(controller) {
        const next = await reader.read();
        if (next.done) {
          controller.close();
          return;
        }
        controller.enqueue(next.value);
      },
      cancel(reason) {
        void reader.cancel(reason).catch(() => undefined);
      },
    }),
  };
}

/**
 * Адаптер ACP: подделка адаптера библиотеки оркестратора.
 *
 * Адаптер открывает сессию в ядре, объявляет её оркестратору и на промпт
 * отвечает началом хода.  На steering он не отвечает: настоящий адаптер такой
 * запрос обрывает, и проверка должна увидеть, что до адаптера он не дошёл.
 */
function fakeAdapter(stream: {
  writable: WritableStream<WireMessage>;
  readable: ReadableStream<WireMessage>;
}): {
  send: (input: ProviderInput) => Promise<void>;
  prompts: ProviderInput[];
  onEvent: (listener: (event: ProviderEvent) => void) => () => void;
} {
  const writer = stream.writable.getWriter();
  const reader = stream.readable.getReader();
  const pending = new Map<string, (result: unknown) => void>();
  const prompts: ProviderInput[] = [];
  const listeners = new Set<(event: ProviderEvent) => void>();
  let counter = 0;

  void (async () => {
    for (;;) {
      const next = await reader.read();
      if (next.done) return;
      const message = next.value;
      if (message.id === undefined || message.id === null) continue;
      const resolve = pending.get(String(message.id));
      if (!resolve) continue;
      pending.delete(String(message.id));
      resolve(message.result);
    }
  })();

  const emit = (event: ProviderEvent): void => {
    for (const listener of listeners) listener(event);
  };

  const call = async (method: string, params: unknown): Promise<unknown> => {
    const id = `adapter-${++counter}`;
    const answer = new Promise<unknown>((resolve) => pending.set(String(id), resolve));
    await writer.write({ jsonrpc: "2.0", id, method, params } as WireMessage);
    return answer;
  };

  return {
    prompts,
    onEvent(listener: (event: ProviderEvent) => void): () => void {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    async send(input: ProviderInput): Promise<void> {
      if (input.type === "session.open") {
        await call("session/new", {
          cwd: input.config?.cwd ?? "/tmp",
          mcpServers: [],
          _meta: { _paseo: { providerOptions: input.config?.providerOptions ?? {} } },
        });
        emit({
          type: "session.opened",
          sessionId: input.sessionId,
          capabilities: ["prompt.message"],
        });
      } else if (input.type === "session.prompt") {
        prompts.push(input);
        const turnId = `acp:${input.prompt?.clientMessageId ?? ""}`;
        emit({
          type: "session.prompt_result",
          sessionId: input.sessionId,
          clientMessageId: input.prompt?.clientMessageId,
          result: { type: "turn", turnId },
        });
        emit({
          type: "session.turn",
          sessionId: input.sessionId,
          turnId,
          state: "started",
        });
      }
    },
  };
}

/** Форма запуска ядра: ход, который не кончается, потому что модель не ответила. */
function serviceForm(lib: string): string {
  return `(progn
  (add-to-list 'load-path ${JSON.stringify(lib)})
  (require 'yeah-acp)
  (defun yeah-check--transport (prompt callback) nil)
  (yeah-acp-serve-socket (getenv "YEAH_ACP_SOCKET") #'yeah-check--transport nil 'local nil))`;
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

  try {
    if (!service.process) {
      throw new Error("плагин не поднял ядро: сервис нашёлся сам, а поднимать было некому");
    }

    // Провод ядра: сначала запись, потом обёртка steering'а.
    const transport = await yeahTransport({
      launch,
      key: "",
      mode: "service",
      serviceName: name,
      service,
    });
    const recorded = recordStream(transport.stream);
    const registry = yeahSteerRegistry();
    const wire = yeahSteerWire(recorded as never, registry);
    const adapter = fakeAdapter(wire as never);

    // Оркестратор: возможности соединения и события сессии.
    const events: ProviderEvent[] = [];
    const connection = yeahSteerConnection(
      {
        version: 1,
        capabilities: ["prompt.message", "prompt.command", "session.configure", "permission"],
        async send(input: ProviderInput): Promise<void> {
          await adapter.send(input);
        },
        onEvent(listener: (event: ProviderEvent) => void): () => void {
          return adapter.onEvent(listener);
        },
        async close(): Promise<void> {},
      } as never,
      registry,
      ["prompt.message", STEER_CAPABILITY],
    );
    connection.onEvent((event: ProviderEvent) => events.push(event));

    await connection.send({
      type: "session.open",
      requestId: "r-1",
      sessionId: "orch-1",
      config: { cwd: workspace ?? lib, providerOptions: {} },
    } as never);

    // Ход начинается и не кончается: модель не ответила.
    await connection.send({
      type: "session.prompt",
      sessionId: "orch-1",
      prompt: {
        clientMessageId: "m-1",
        delivery: "auto",
        input: { type: "message", content: [{ type: "text", text: "сделай дело" }] },
      },
    } as never);

    // Уточнение приходит посреди хода.
    await connection.send({
      type: "session.prompt",
      sessionId: "orch-1",
      prompt: {
        clientMessageId: "m-2",
        delivery: "steer",
        input: { type: "message", content: [{ type: "text", text: "остановись на файле X" }] },
      },
    } as never);

    const steerRequest = recorded.log.find(
      (message) => message.method === "session/steer",
    );
    const cancelRequest = recorded.log.find(
      (message) => message.method === "session/cancel",
    );
    const steerResult = events.find(
      (event) =>
        event.type === "session.prompt_result" && event.clientMessageId === "m-2",
    );
    const opened = events.find((event) => event.type === "session.opened");

    const report = {
      ok: true,
      steerReachedCore: Boolean(steerRequest),
      steerParams: (steerRequest?.params ?? null) as unknown,
      turnInterrupted: Boolean(cancelRequest),
      adapterSawSteer: adapter.prompts.some(
        (input) => input.prompt?.clientMessageId === "m-2",
      ),
      steerCapability: connection.capabilities.includes(STEER_CAPABILITY),
      sessionAnnouncedSteer: (opened?.capabilities ?? []).includes(STEER_CAPABILITY),
      reportedTurn: steerResult?.result?.turnId ?? null,
      steerFailed: steerResult?.result?.type === "failed",
      steerError: steerResult?.result?.error?.message ?? null,
    };
    process.stdout.write(`${JSON.stringify(report)}\n`);
  } finally {
    await service.close();
  }
}

main().catch((error: unknown) => {
  process.stderr.write(
    `steer-проверка: ${error instanceof Error ? error.message : String(error)}\n`,
  );
  process.exit(1);
});
