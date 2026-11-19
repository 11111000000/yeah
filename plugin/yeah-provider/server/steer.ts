/**
 * Steering: сообщение, пришедшее посреди хода.
 *
 * Оркестратор умеет спросить агента «а теперь сделай вот это», не прерывая
 * ход: такое сообщение называется steering, и провайдер обязан объявить
 * возможность `prompt.steer`.  Адаптер ACP библиотеки оркестратора такой
 * возможности не знает: он объявляет четыре, а запрос со `delivery: "steer"`
 * обрывает текущий ход и начинает новый.  Это замена хода, а не steering.
 *
 * Поэтому steering делает плагин: он перехватывает такой запрос, отправляет
 * ядру `session/steer` и отвечает оркестратору, что ход тот же — с тем же
 * идентификатором.  Оркестратор проверяет именно это: steering, который
 * дошёл не того хода, он не принимает.
 *
 * Два факта нужны для этого, и оба приходят с провода:
 *
 *   1. идентификатор сессии ядра — им ядро называет свою сессию в
 *      `session/steer`; оркестратор знает только свой идентификатор;
 *   2. идентификатор хода — им оркестратор проверяет, что steering дошёл
 *      именно того хода, который идёт сейчас.
 *
 * Идентификатор сессии ядра плагин узнаёт из ответа на `session/new`, а какой
 * сессии оркестратора он принадлежит — из метки, которую плагин кладёт в
 * параметры открытия сессии.  Метка едет в `_meta` запроса, и адаптер
 * перекладывает её без изменений.
 */
import type { AcpStream, AcpStreamMessage } from "@getpaseo/plugin/server/acp";
import type {
  ProviderConnection,
  ProviderEvent,
  ProviderInput,
  ProviderPrompt,
} from "@getpaseo/plugin/server/provider";

import { asRecord } from "../shared/vocabulary";

/** Ключ, под которым метка сессии лежит в параметрах открытия сессии. */
export const STEER_MARKER = "yeah.session";

/** Возможность, которой оркестратор признаёт steering. */
export const STEER_CAPABILITY = "prompt.steer";

/** Сколько плагин ждёт ответа ядра на steering, миллисекунд. */
const STEER_TIMEOUT_MS = 10_000;

/** Запрос в ядро по личному каналу плагина. */
export type YeahSteerCall = (method: string, params: unknown) => Promise<unknown>;

/** Что реестр знает о сессии оркестратора. */
export interface YeahSteerTarget {
  /** Идентификатор сессии в ядре. */
  acpSessionId: string;
  /** Отправить запрос в ядро. */
  call: YeahSteerCall;
}

/** Реестр сессий: сессия оркестратора и сессия ядра. */
export interface YeahSteerRegistry {
  /** Сессия SESSIONID оркестратора — это сессия ACPID ядра. */
  bind(sessionId: string, acpSessionId: string, call: YeahSteerCall): void;
  /** Что известно о сессии SESSIONID. */
  target(sessionId: string): YeahSteerTarget | undefined;
  /** Забыть сессию SESSIONID. */
  forget(sessionId: string): void;
}

/** Реестр сессий плагина: steering. */
export function yeahSteerRegistry(): YeahSteerRegistry {
  const targets = new Map<string, YeahSteerTarget>();
  return {
    bind(sessionId, acpSessionId, call) {
      targets.set(sessionId, { acpSessionId, call });
    },
    target(sessionId) {
      return targets.get(sessionId);
    },
    forget(sessionId) {
      targets.delete(sessionId);
    },
  };
}

/** Запрос открытия сессии: такие запросы интересуют плагина. */
type SessionOpenInput = Extract<ProviderInput, { type: "session.open" }>;

/** Запрос промпта: такие запросы интересуют плагина. */
type SessionPromptInput = Extract<ProviderInput, { type: "session.prompt" }>;

/**
 * Метка сессии в запросе открытия.
 *
 * Метка кладётся в параметры открытия сессии, потому что адаптер перекладывает
 * их в `_meta` запроса `session/new` без изменений — и больше в проводе нет
 * места, где плагин мог бы оставить своё слово.
 */
export function yeahSteerMarker(sessionId: string): Record<string, unknown> {
  return { [STEER_MARKER]: sessionId };
}

/** Поле сообщения, если оно есть. */
function fieldOf(message: AcpStreamMessage, name: string): unknown {
  const record = message as unknown as Record<string, unknown>;
  return record[name];
}

/**
 * Прочитать метку сессии из запроса к ядру.
 *
 * Метка лежит в `_meta` под именем оркестратора, дальше — в параметрах
 * провайдера, далье — под ключом плагина.  Путь длинный, и каждый его шаг —
 * чужое решение: адаптер складывает `_meta` так, как сложил.  Метки нет — значит
 * запрос не наш, и плагин его не трогает.
 */
function markerOf(message: AcpStreamMessage): string | undefined {
  if (!("method" in message)) return undefined;
  if (message.method !== "session/new" && message.method !== "session/load") return undefined;
  const params = asRecord(fieldOf(message, "params"));
  const meta = asRecord(params._meta);
  const paseo = asRecord(meta._paseo);
  const options = asRecord(paseo.providerOptions);
  const yeah = asRecord(options.yeah);
  const marker = yeah[STEER_MARKER];
  return typeof marker === "string" && marker.length > 0 ? marker : undefined;
}

/** Идентификатор сессии ядра в запросе загрузки сессии. */
function loadedSessionId(message: AcpStreamMessage): string | undefined {
  const params = asRecord(fieldOf(message, "params"));
  const id = params.sessionId;
  return typeof id === "string" && id.length > 0 ? id : undefined;
}

/** Идентификатор сессии ядра в ответе на открытие сессии. */
function openedSessionId(message: AcpStreamMessage): string | undefined {
  const result = asRecord(fieldOf(message, "result"));
  const id = result.sessionId;
  return typeof id === "string" && id.length > 0 ? id : undefined;
}

/** Ответ на запрос: ошибка или результат. */
function answerOf(message: AcpStreamMessage): { result?: unknown; error?: Error } {
  const failure = asRecord(fieldOf(message, "error"));
  if (typeof failure.message === "string") {
    return { error: new Error(failure.message) };
  }
  return { result: fieldOf(message, "result") };
}

/**
 * Обернуть поток провода так, чтобы плагин видел создание сессии ядра и мог
 * слать в ядро `session/steer` мимо адаптера.
 *
 * Адаптер не должен видеть эти запросы: он считает их запросами ядра и
 * ответил бы на них сам.  Поэтому запросы плагина идут в провод по своему
 * каналу, а ответы ядра на них забираются из провода и адаптеру не показываются.
 */
export function yeahSteerWire(stream: AcpStream, registry: YeahSteerRegistry): AcpStream {
  const writer = stream.writable.getWriter();
  const reader = stream.readable.getReader();
  const pending = new Map<
    string,
    { resolve: (value: unknown) => void; reject: (error: Error) => void }
  >();
  // Метка сессии по идентификатору запроса: запрос помечен, ответ приходит по
  // тому же идентификатору.
  const markers = new Map<string, { marker: string; sessionId?: string }>();
  let counter = 0;

  const call: YeahSteerCall = (method, params) => {
    const id = `yeah-steer-${++counter}`;
    const answer = new Promise<unknown>((resolve, reject) => {
      pending.set(id, { resolve, reject });
      const timer = setTimeout(() => {
        const entry = pending.get(id);
        if (!entry) return;
        pending.delete(id);
        entry.reject(new Error(`the core did not answer ${method} in time`));
      }, STEER_TIMEOUT_MS);
      timer.unref?.();
    });
    void writer
      .write({ jsonrpc: "2.0", id, method, params } as AcpStreamMessage)
      .catch((error: unknown) => {
        const entry = pending.get(id);
        if (!entry) return;
        pending.delete(id);
        entry.reject(error instanceof Error ? error : new Error(String(error)));
      });
    return answer;
  };

  const writable = new WritableStream<AcpStreamMessage>({
    async write(message) {
      const marker = markerOf(message);
      if (marker !== undefined && "id" in message && message.id !== null) {
        console.log(`[yeah] steering: метка ${marker} в запросе ${String(message.id)}`);
        markers.set(String(message.id), { marker, sessionId: loadedSessionId(message) });
      }
      await writer.write(message);
    },
    async close() {
      await writer.close().catch(() => undefined);
    },
    async abort(reason) {
      await writer.abort(reason).catch(() => undefined);
    },
  });

  const readable = new ReadableStream<AcpStreamMessage>({
    async pull(controller) {
      let next;
      try {
        next = await reader.read();
      } catch (error) {
        controller.error(error);
        return;
      }
      if (next.done) {
        controller.close();
        return;
      }
      const message = next.value as AcpStreamMessage;
      // Ответ на наш запрос: ядро ответило, адаптер об этом не знает.
      const id = "id" in message && message.id !== null ? String(message.id) : "";
      const entry = pending.get(id);
      if (entry) {
        pending.delete(id);
        const answer = answerOf(message);
        if (answer.error) entry.reject(answer.error);
        else entry.resolve(answer.result);
        return;
      }
      // Ответ на запрос открытия сессии: он называет сессию ядра.
      const marked = markers.get(id);
      if (marked) {
        markers.delete(id);
        const acpSessionId = marked.sessionId ?? openedSessionId(message);
        if (acpSessionId) {
          console.log(
            `[yeah] steering: сессия ${marked.marker} оркестратора ↔ сессия ${acpSessionId} ядра`,
          );
          registry.bind(marked.marker, acpSessionId, call);
        }
      }
      controller.enqueue(message);
    },
    cancel(reason) {
      void reader.cancel(reason).catch(() => undefined);
    },
  });

  return { writable, readable };
}

/**
 * Текст steering'а: то, что человек написал посреди хода.
 *
 * Команда — не текст: ядро принимает уточнение строкой, и команда строкой не
 * является.  Steering без текста нечего доставлять, и плагин говорит об этом
 * прямо, вместо того чтобы отдать ядру пустоту.
 */
export function yeahSteerText(prompt: ProviderPrompt): string | undefined {
  if (prompt.input.type !== "message") return undefined;
  const parts = prompt.input.content
    .filter((part) => part.type === "text")
    .map((part) => part.text)
    .filter((text) => text.length > 0);
  if (parts.length === 0) return undefined;
  return parts.join("\n");
}

/** Добавить возможность steering к списку возможностей. */
function withSteer(capabilities: readonly string[]): string[] {
  return capabilities.includes(STEER_CAPABILITY)
    ? [...capabilities]
    : [...capabilities, STEER_CAPABILITY];
}

/**
 * Обернуть соединение провайдера так, чтобы steering доходил до ядра, а ход
 * оставался ходом.
 *
 * Возможность steering объявляется в двух местах, и оба нужны: в списке
 * возможностей соединения — чтобы оркестратор принял соединение, и в событии
 * открытия сессии — чтобы оркестратор принял steering этой сессии.
 *
 * Объявляется только тогда, когда оркестратор её предложил: соединение, которое
 * выбрало не предложенную возможность, оркестратор вовсе не принимает.
 */
export function yeahSteerConnection(
  inner: ProviderConnection,
  registry: YeahSteerRegistry,
  offered: readonly string[] = [STEER_CAPABILITY],
): ProviderConnection {
  const listeners = new Set<(event: ProviderEvent) => void>();
  // Идентификатор хода, который идёт сейчас, по сессии оркестратора.
  const turns = new Map<string, string>();
  const steerable = offered.includes(STEER_CAPABILITY);

  const publish = (event: ProviderEvent): void => {
    for (const listener of listeners) listener(event);
  };

  const refuse = (
    sessionId: string,
    clientMessageId: string,
    message: string,
  ): void => {
    console.log(`[yeah] steering: отказ в сессии ${sessionId}: ${message}`);
    publish({
      type: "session.prompt_result",
      sessionId,
      clientMessageId,
      result: { type: "failed", error: { message } },
    });
  };

  inner.onEvent((event) => {
    if (event.type === "session.prompt_result" && event.result.type === "turn") {
      turns.set(event.sessionId, event.result.turnId);
    } else if (event.type === "session.turn") {
      if (event.state === "started") turns.set(event.sessionId, event.turnId);
      else turns.delete(event.sessionId);
    }
    if (event.type === "session.opened" && steerable) {
      console.log(
        `[yeah] steering: сессия ${event.sessionId} объявляет возможности ` +
          `${withSteer(event.capabilities).join(", ")}`,
      );
      publish({ ...event, capabilities: withSteer(event.capabilities) });
      return;
    }
    publish(event);
  });

  const steer = async (input: SessionPromptInput): Promise<void> => {
    const sessionId = input.sessionId;
    const clientMessageId = input.prompt.clientMessageId;
    const turnId = turns.get(sessionId);
    const target = registry.target(sessionId);
    const text = yeahSteerText(input.prompt);
    console.log(
      `[yeah] steering: запрос в сессии ${sessionId}, ход ${turnId ?? "нет"}, ` +
        `ядро ${target?.acpSessionId ?? "не знает"}`,
    );
    if (!turnId) {
      refuse(sessionId, clientMessageId, "the session has no running turn");
      return;
    }
    if (!target) {
      refuse(sessionId, clientMessageId, "the core does not know this session");
      return;
    }
    if (text === undefined) {
      refuse(sessionId, clientMessageId, "the steering message carries no text");
      return;
    }
    try {
      await target.call("session/steer", { sessionId: target.acpSessionId, prompt: text });
    } catch (error) {
      refuse(
        sessionId,
        clientMessageId,
        error instanceof Error ? error.message : String(error),
      );
      return;
    }
    publish({
      type: "session.prompt_result",
      sessionId,
      clientMessageId,
      result: { type: "steer", turnId },
    });
  };

  return {
    version: inner.version,
    capabilities: steerable ? withSteer(inner.capabilities) : [...inner.capabilities],
    async send(input: ProviderInput): Promise<void> {
      if (input.type === "session.prompt" && input.prompt.delivery === "steer") {
        // Адаптер обрывает текущий ход на такой запрос и начинает новый.
        // Steering не заменяет ход, поэтому запрос не доходит до адаптера.
        console.log(`[yeah] steering: перехвачен запрос с delivery=steer`);
        await steer(input);
        return;
      }
      if (input.type === "session.open") {
        await inner.send(markedOpen(input));
        return;
      }
      await inner.send(input);
    },
    onEvent(listener: (event: ProviderEvent) => void): () => void {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    async close(): Promise<void> {
      await inner.close();
    },
  };
}

/**
 * Пометить открытие сессии меткой плагина.
 *
 * Метка нужна ядру не для работы, а для плагина: по ней плагин узнаёт, какой
 * сессии оркестратора принадлежит ответ ядра на открытие сессии.
 */
export function markedOpen(input: SessionOpenInput): SessionOpenInput {
  const options = input.config.providerOptions ?? {};
  const yeah = asRecord(options.yeah);
  return {
    ...input,
    config: {
      ...input.config,
      providerOptions: {
        ...options,
        yeah: { ...yeah, ...yeahSteerMarker(input.sessionId) },
      },
    },
  };
}
