/**
 * Расход хода на пути к оркестратору.
 *
 * Ядро Yeah отдаёт токены хода двумя путями: полем `usage` в ответе
 * `session/prompt` (так читает ACP-клиент оркестратора) и уведомлением
 * `yeah/usage` (так читает плагин).  Плагину нужен второй путь: соединение
 * оркестратора отбрасывает ответ на `session/prompt` и оставляет от него
 * один `stopReason`, а уведомление с чужим методом доходит целиком.
 *
 * Перевод один: уведомление ядра становится событием провайдера
 * `session.usage`.  Только такое событие оркестратор переносит в расход
 * агента, и только в нём есть токены хода: обновление контекста ACP
 * (`usage_update`) несёт размер окна, а не потраченные токены.
 */
import type { AcpVendorUpdate } from "@getpaseo/plugin/server/acp";
import type {
  ProviderConnection,
  ProviderEvent,
  ProviderInput,
  ProviderUsage,
} from "@getpaseo/plugin/server/provider";

import { USAGE_KEY, USAGE_METHOD } from "../shared/vocabulary";

// Метод и ключ расхода хода — словарь Yeah, и он живёт вместе с остальным
// словарём: его читает и процессный путь плагина, и сервисный.
export { USAGE_METHOD, USAGE_KEY };

/**
 * Реестр сессий: кто и как отдаёт события оркестратору.
 *
 * Соединитель оркестратора знает сессию, а уведомление ядра приходит без
 * указания, кому оно принадлежит: сессию называет контекст соединения.
 * Реестр сопоставляет одно с другим, чтобы расход хода уехал в свою
 * сессию, а не в чужую.
 */
export interface YeahUsageRegistry {
  /** Сессия SESSIONID открыта: REPORT получает её расход хода. */
  attach(sessionId: string, report: (usage: ProviderUsage) => void): void;
  /** Сессия SESSIONID закрыта: её расход больше не приходит. */
  detach(sessionId: string): void;
  /** Расход хода пришёл в сессию SESSIONID. */
  report(sessionId: string, usage: ProviderUsage): void;
}

/** Реестр сессий плагина: расход хода. */
export function yeahUsageRegistry(): YeahUsageRegistry {
  const reporters = new Map<string, (usage: ProviderUsage) => void>();
  return {
    attach(sessionId, report) {
      reporters.set(sessionId, report);
    },
    detach(sessionId) {
      reporters.delete(sessionId);
    },
    report(sessionId, usage) {
      const report = reporters.get(sessionId);
      if (!report) return;
      report(usage);
    },
  };
}

/**
 * Значение объекта: любой не-объект — пустой объект.
 *
 * Провод присылает то, что прислал, и разбирать это — работа плагина: ядро
 * не знает, как выглядит сообщение оркестратора, а оркестратор не знает, как
 * выглядит словарь ядра.
 */
function asRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

/** Число поля, если оно есть и это число. */
function numberOf(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

/**
 * Достать расход хода из параметров уведомления.
 *
 * Расход без токенов — не расход: уведомление без чисел нечего переводить,
 * и оркестратору нечего показывать.
 */
export function yeahUsageOf(params: unknown): ProviderUsage | null {
  const record = asRecord(params);
  const input = numberOf(record.inputTokens);
  const output = numberOf(record.outputTokens);
  if (input === undefined && output === undefined) return null;
  const usage: ProviderUsage = {};
  if (input !== undefined) usage.inputTokens = input;
  if (output !== undefined) usage.outputTokens = output;
  return usage;
}

/**
 * Перевести уведомление ядра о расходе хода в событие провайдера.
 *
 * Само уведомление оркестратору ничего не несёт: у провайдера нет такого
 * вида события, и перевод живёт в реестре, который знает сессию.
 */
export function yeahUsageNotification(
  registry: YeahUsageRegistry,
): (
  notification: { method: string; params: unknown },
  context: { sessionId: string },
) => AcpVendorUpdate | null {
  return (notification, context) => {
    if (notification.method !== USAGE_METHOD) return null;
    const usage = yeahUsageOf(notification.params);
    if (!usage) return null;
    registry.report(context.sessionId, usage);
    return null;
  };
}

/** Сессия ввода провайдера: пустая строка, если её нет. */
function sessionIdOf(input: ProviderInput): string {
  const id = (input as { sessionId?: unknown }).sessionId;
  return typeof id === "string" && id.length > 0 ? id : "";
}

/**
 * Обернуть соединение провайдера так, чтобы расход хода доезжал до оркестратора.
 *
 * Соединитель оркестратора берёт из ответа на `session/prompt` один
 * `stopReason` и выбрасывает остальное, поэтому плагин смотрит на уведомление
 * ядра и отдаёт расход сам.
 *
 * Расход собирается из двух частей, и обе нужны оркестратору: обновление
 * контекста ACP (`usage_update`) несёт размер окна, а уведомление ядра несёт
 * токены хода.  Порядок их обработки задаёт оркестратор, поэтому плагин не
 * отдаёт расход по частям, а дополняет одну часть другой: кто бы ни пришёл
 * последним, в счётчике агента стоят и токены хода, и размер окна.
 *
 * События соединения идут дальше как есть: плагин добавляет расход и ничего
 * не меняет.
 */
export function yeahUsageConnection(
  inner: ProviderConnection,
  registry: YeahUsageRegistry,
): ProviderConnection {
  const listeners = new Set<(event: ProviderEvent) => void>();
  let sessionId = "";
  // Размер окна и стоимость -- то, что знает соединение о контексте.
  let context: ProviderUsage = {};
  // Токены хода -- то, что пришло от ядра.
  let tokens: ProviderUsage = {};

  const publish = (): void => {
    const usage: ProviderUsage = { ...context, ...tokens };
    if (Object.keys(usage).length === 0) return;
    const event: ProviderEvent = { type: "session.usage", sessionId, usage };
    for (const listener of listeners) listener(event);
  };

  inner.onEvent((event) => {
    if (event.type === "session.usage") {
      context = { ...context, ...event.usage };
      publish();
      return;
    }
    for (const listener of listeners) listener(event);
  });

  return {
    version: inner.version,
    capabilities: inner.capabilities,
    async send(input: ProviderInput): Promise<void> {
      const opened = sessionIdOf(input);
      if (opened) {
        sessionId = opened;
        registry.attach(sessionId, (usage) => {
          tokens = { ...tokens, ...usage };
          publish();
        });
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
      if (sessionId) registry.detach(sessionId);
      await inner.close();
    },
  };
}
