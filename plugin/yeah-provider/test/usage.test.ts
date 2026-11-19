import assert from "node:assert/strict";
import { test } from "node:test";
import type {
  ProviderConnection,
  ProviderEvent,
  ProviderInput,
} from "@getpaseo/plugin/server/provider";
import {
  USAGE_KEY,
  USAGE_METHOD,
  yeahUsageConnection,
  yeahUsageNotification,
  yeahUsageOf,
  yeahUsageRegistry,
} from "../server/usage";

/**
 * Соединение, которое никуда не ходит.
 *
 * Проверка смотрит на то, что плагин делает с событиями и вводами, а сам
 * провод ей не нужен: соединение-обманка помогает увидеть, что события
 * соединения идут дальше как есть, а расход хода добавляется к ним.
 */
function fakeConnection(): {
  connection: ProviderConnection;
  sent: ProviderInput[];
  emit: (event: ProviderEvent) => void;
} {
  const listeners = new Set<(event: ProviderEvent) => void>();
  const sent: ProviderInput[] = [];
  return {
    sent,
    emit: (event: ProviderEvent) => {
      for (const listener of listeners) listener(event);
    },
    connection: {
      version: 1,
      capabilities: [],
      async send(input: ProviderInput): Promise<void> {
        sent.push(input);
      },
      onEvent(listener: (event: ProviderEvent) => void): () => void {
        listeners.add(listener);
        return () => {
          listeners.delete(listener);
        };
      },
      async close(): Promise<void> {},
    },
  };
}

/** Ввод открытия сессии: так оркестратор открывает сессию у провайдера. */
function openSession(sessionId: string): ProviderInput {
  return {
    type: "session.open",
    requestId: "r-1",
    sessionId,
    config: {
      cwd: "/tmp",
      env: {},
      mcpServers: {},
      toolPolicy: { preapproved: [] },
      settings: {},
      persist: false,
    },
    history: "skip",
  };
}

test("расход хода читается из параметров уведомления", () => {
  assert.deepEqual(
    yeahUsageOf({ sessionId: "s-1", inputTokens: 1200, outputTokens: 34 }),
    { inputTokens: 1200, outputTokens: 34 },
  );
});

test("уведомление без токенов — не расход", () => {
  assert.equal(yeahUsageOf({ sessionId: "s-1" }), null);
  assert.equal(yeahUsageOf("not an object"), null);
  assert.equal(yeahUsageOf({ inputTokens: "many" }), null);
});

test("уведомление с чужим методом игнорируется", () => {
  const registry = yeahUsageRegistry();
  const translate = yeahUsageNotification(registry);
  const update = translate(
    { method: "session/update", params: { inputTokens: 10 } },
    { sessionId: "s-1" },
  );
  assert.equal(update, null);
});

test("реестр отдаёт расход хода той сессии, которой он принадлежит", () => {
  const registry = yeahUsageRegistry();
  const seen: unknown[] = [];
  registry.attach("s-1", (usage) => seen.push(usage));
  registry.report("s-1", { inputTokens: 1200, outputTokens: 34 });
  assert.deepEqual(seen, [{ inputTokens: 1200, outputTokens: 34 }]);
});

test("расход хода сессии, которой нет, никому не достаётся", () => {
  const registry = yeahUsageRegistry();
  const seen: unknown[] = [];
  registry.attach("s-1", (usage) => seen.push(usage));
  registry.report("s-2", { inputTokens: 1200 });
  assert.deepEqual(seen, []);
});

test("перевод уведомления кладёт расход в свою сессию", () => {
  const registry = yeahUsageRegistry();
  const seen: unknown[] = [];
  registry.attach("s-7", (usage) => seen.push(usage));
  const translate = yeahUsageNotification(registry);
  const update = translate(
    { method: USAGE_METHOD, params: { inputTokens: 1200, outputTokens: 34 } },
    { sessionId: "s-7" },
  );
  // У провайдера нет вида события для расхода: перевод живёт в реестре.
  assert.equal(update, null);
  assert.deepEqual(seen, [{ inputTokens: 1200, outputTokens: 34 }]);
});

test("соединение отдаёт события соединения как есть", async () => {
  const registry = yeahUsageRegistry();
  const fake = fakeConnection();
  const connection = yeahUsageConnection(fake.connection, registry);
  const events: ProviderEvent[] = [];
  connection.onEvent((event) => events.push(event));
  fake.emit({ type: "session.ready", sessionId: "s-3", requestId: "r-1" });
  assert.deepEqual(events, [
    { type: "session.ready", sessionId: "s-3", requestId: "r-1" },
  ]);
});

test("расход хода доезжает до оркестратора после открытия сессии", async () => {
  const registry = yeahUsageRegistry();
  const fake = fakeConnection();
  const connection = yeahUsageConnection(fake.connection, registry);
  const events: ProviderEvent[] = [];
  connection.onEvent((event) => events.push(event));
  await connection.send(openSession("s-9"));
  assert.equal(fake.sent.length, 1);
  const translate = yeahUsageNotification(registry);
  translate(
    { method: USAGE_METHOD, params: { inputTokens: 1200, outputTokens: 34 } },
    { sessionId: "s-9" },
  );
  assert.deepEqual(events, [
    {
      type: "session.usage",
      sessionId: "s-9",
      usage: { inputTokens: 1200, outputTokens: 34 },
    },
  ]);
});

test("обновление контекста не затирает токены хода", async () => {
  const registry = yeahUsageRegistry();
  const fake = fakeConnection();
  const connection = yeahUsageConnection(fake.connection, registry);
  const events: ProviderEvent[] = [];
  connection.onEvent((event) => events.push(event));
  await connection.send(openSession("s-11"));
  const translate = yeahUsageNotification(registry);
  translate(
    { method: USAGE_METHOD, params: { inputTokens: 1200, outputTokens: 34 } },
    { sessionId: "s-11" },
  );
  // Оркестратор обрабатывает обновление контекста позже уведомления ядра:
  // кто бы ни пришёл последним, в счётчике должны стоять обе части расхода.
  fake.emit({
    type: "session.usage",
    sessionId: "s-11",
    usage: { contextWindowUsedTokens: 4096, contextWindowMaxTokens: 32000 },
  });
  assert.deepEqual(events[events.length - 1], {
    type: "session.usage",
    sessionId: "s-11",
    usage: {
      inputTokens: 1200,
      outputTokens: 34,
      contextWindowUsedTokens: 4096,
      contextWindowMaxTokens: 32000,
    },
  });
});

test("токены хода не затирают обновление контекста", async () => {
  const registry = yeahUsageRegistry();
  const fake = fakeConnection();
  const connection = yeahUsageConnection(fake.connection, registry);
  const events: ProviderEvent[] = [];
  connection.onEvent((event) => events.push(event));
  await connection.send(openSession("s-12"));
  fake.emit({
    type: "session.usage",
    sessionId: "s-12",
    usage: { contextWindowUsedTokens: 4096, contextWindowMaxTokens: 32000 },
  });
  const translate = yeahUsageNotification(registry);
  translate(
    { method: USAGE_METHOD, params: { inputTokens: 1200, outputTokens: 34 } },
    { sessionId: "s-12" },
  );
  assert.deepEqual(events[events.length - 1], {
    type: "session.usage",
    sessionId: "s-12",
    usage: {
      inputTokens: 1200,
      outputTokens: 34,
      contextWindowUsedTokens: 4096,
      contextWindowMaxTokens: 32000,
    },
  });
});

test("закрытая сессия больше не получает расход хода", async () => {
  const registry = yeahUsageRegistry();
  const fake = fakeConnection();
  const connection = yeahUsageConnection(fake.connection, registry);
  const events: ProviderEvent[] = [];
  connection.onEvent((event) => events.push(event));
  await connection.send(openSession("s-10"));
  await connection.close();
  const translate = yeahUsageNotification(registry);
  translate(
    { method: USAGE_METHOD, params: { inputTokens: 1200 } },
    { sessionId: "s-10" },
  );
  assert.deepEqual(events, []);
});

test("ключ объявления расхода — имя метода без слеша", () => {
  assert.equal(USAGE_KEY, "yeah.usage");
  assert.equal(USAGE_METHOD, "yeah/usage");
});
