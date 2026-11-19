import assert from "node:assert/strict";
import { test } from "node:test";
import type { AcpStream, AcpStreamMessage } from "@getpaseo/plugin/server/acp";
import type {
  ProviderConnection,
  ProviderEvent,
  ProviderInput,
} from "@getpaseo/plugin/server/provider";
import {
  STEER_CAPABILITY,
  STEER_MARKER,
  yeahSteerConnection,
  yeahSteerRegistry,
  yeahSteerText,
  yeahSteerWire,
} from "../server/steer";

/**
 * Поддельное ядро на проводе.
 *
 * Ядро отвечает на `initialize' и `session/new' и записывает всё, что до него
 * дошло: проверка смотрит, что steering дошёл именно как `session/steer'.
 */
function fakeCore(): { stream: AcpStream; received: AcpStreamMessage[] } {
  const toCore = new TransformStream<AcpStreamMessage, AcpStreamMessage>();
  const fromCore = new TransformStream<AcpStreamMessage, AcpStreamMessage>();
  const coreWriter = fromCore.writable.getWriter();
  const coreReader = toCore.readable.getReader();
  const received: AcpStreamMessage[] = [];

  void (async () => {
    for (;;) {
      const next = await coreReader.read();
      if (next.done) return;
      const message = next.value;
      received.push(message);
      if (!("id" in message) || message.id === null) continue;
      const method = "method" in message ? message.method : "";
      const result =
        method === "initialize"
          ? { protocolVersion: 1, agentCapabilities: {} }
          : method === "session/new"
            ? { sessionId: "core-session-1" }
            : method === "session/steer"
              ? { inputId: "input-1" }
              : {};
      await coreWriter.write({ jsonrpc: "2.0", id: message.id, result });
    }
  })();

  return {
    received,
    stream: { writable: toCore.writable, readable: fromCore.readable },
  };
}

/**
 * Поддельный адаптер ACP: он ведёт себя как адаптер библиотеки оркестратора.
 *
 * Адаптер открывает сессию в ядре, объявляет её оркестратору и на промпт
 * отвечает началом хода.  На steering он не отвечает: настоящий адаптер такой
 * запрос обрывает, и проверка должна увидеть, что до адаптера он не дошёл.
 */
function fakeAdapter(stream: AcpStream): {
  connection: ProviderConnection;
  sent: ProviderInput[];
} {
  const listeners = new Set<(event: ProviderEvent) => void>();
  const sent: ProviderInput[] = [];
  const writer = stream.writable.getWriter();
  const reader = stream.readable.getReader();
  const pending = new Map<string, (result: unknown) => void>();
  let counter = 0;

  void (async () => {
    for (;;) {
      const next = await reader.read();
      if (next.done) return;
      const message = next.value;
      if (!("id" in message) || message.id === null) continue;
      const resolve = pending.get(String(message.id));
      if (!resolve) continue;
      pending.delete(String(message.id));
      resolve((message as { result?: unknown }).result);
    }
  })();

  const emit = (event: ProviderEvent): void => {
    for (const listener of listeners) listener(event);
  };

  const call = async (method: string, params: unknown): Promise<unknown> => {
    const id = `adapter-${++counter}`;
    const answer = new Promise<unknown>((resolve) => pending.set(id, resolve));
    await writer.write({ jsonrpc: "2.0", id, method, params });
    return answer;
  };

  return {
    sent,
    connection: {
      version: 1,
      capabilities: ["prompt.message", "prompt.command", "session.configure", "permission"],
      async send(input: ProviderInput): Promise<void> {
        sent.push(input);
        if (input.type === "session.open") {
          const result = (await call("session/new", {
            cwd: input.config.cwd,
            mcpServers: [],
            _meta: { _paseo: { providerOptions: input.config.providerOptions } },
          })) as { sessionId?: string };
          emit({
            type: "session.opened",
            requestId: input.requestId,
            sessionId: input.sessionId,
            capabilities: ["prompt.message"],
            restoration: "core",
            cwd: input.config.cwd,
          });
          emit({ type: "session.ready", requestId: input.requestId, sessionId: input.sessionId });
          void result;
        } else if (input.type === "session.prompt") {
          const turnId = `acp:${input.prompt.clientMessageId}`;
          emit({
            type: "session.prompt_result",
            sessionId: input.sessionId,
            clientMessageId: input.prompt.clientMessageId,
            result: { type: "turn", turnId },
          });
          emit({ type: "session.turn", sessionId: input.sessionId, turnId, state: "started" });
        }
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

/** Ввод промпта: так оркестратор говорит агенту. */
function prompt(
  sessionId: string,
  clientMessageId: string,
  delivery: "auto" | "steer",
  text: string,
): ProviderInput {
  return {
    type: "session.prompt",
    sessionId,
    prompt: {
      clientMessageId,
      delivery,
      input: { type: "message", content: [{ type: "text", text }] },
    },
  };
}

test("соединение объявляет steering, когда оркестратор его предложил", async () => {
  const registry = yeahSteerRegistry();
  const core = fakeCore();
  const wire = yeahSteerWire(core.stream, registry);
  const adapter = fakeAdapter(wire);
  const connection = yeahSteerConnection(adapter.connection, registry, [
    "prompt.message",
    STEER_CAPABILITY,
  ]);
  assert.ok(connection.capabilities.includes(STEER_CAPABILITY));
});

test("сессия объявляет steering, когда оркестратор его не предложил", async () => {
  const registry = yeahSteerRegistry();
  const core = fakeCore();
  const wire = yeahSteerWire(core.stream, registry);
  const adapter = fakeAdapter(wire);
  const connection = yeahSteerConnection(adapter.connection, registry, ["prompt.message"]);
  assert.ok(!connection.capabilities.includes(STEER_CAPABILITY));
});

test("открытие сессии несёт метку плагина", async () => {
  const registry = yeahSteerRegistry();
  const core = fakeCore();
  const wire = yeahSteerWire(core.stream, registry);
  const adapter = fakeAdapter(wire);
  const connection = yeahSteerConnection(adapter.connection, registry, [
    "prompt.message",
    STEER_CAPABILITY,
  ]);
  await connection.send(openSession("orch-1"));
  const opened = adapter.sent[0];
  assert.ok(opened.type === "session.open");
  const options = opened.config.providerOptions ?? {};
  const yeah = (options as Record<string, Record<string, unknown>>).yeah;
  assert.equal(yeah[STEER_MARKER], "orch-1");
});

test("steering доходит до ядра как session/steer и не обрывает ход", async () => {
  const registry = yeahSteerRegistry();
  const core = fakeCore();
  const wire = yeahSteerWire(core.stream, registry);
  const adapter = fakeAdapter(wire);
  const connection = yeahSteerConnection(adapter.connection, registry, [
    "prompt.message",
    STEER_CAPABILITY,
  ]);
  const events: ProviderEvent[] = [];
  connection.onEvent((event) => events.push(event));

  await connection.send(openSession("orch-1"));
  await connection.send(prompt("orch-1", "m-1", "auto", "работай"));
  await connection.send(prompt("orch-1", "m-2", "steer", "остановись на файле X"));

  // Ядро получило steering, а не новый ход.
  const request = core.received.find(
    (message) => "method" in message && message.method === "session/steer",
  );
  assert.ok(request, "the core did not receive the steering");
  assert.deepEqual((request as { params?: unknown }).params, {
    sessionId: "core-session-1",
    prompt: "остановись на файле X",
  });

  // Адаптер получил один промпт: тот, что начал ход.  Steering до него не дошёл.
  const prompts = adapter.sent.filter((input) => input.type === "session.prompt");
  assert.equal(prompts.length, 1);

  // Оркестратору сказано, что ход тот же.
  const result = events.find(
    (event) => event.type === "session.prompt_result" && event.clientMessageId === "m-2",
  );
  assert.ok(result && result.type === "session.prompt_result");
  assert.deepEqual(result.result, { type: "steer", turnId: "acp:m-1" });
});

test("steering без идущего хода — отказ, а не новый ход", async () => {
  const registry = yeahSteerRegistry();
  const core = fakeCore();
  const wire = yeahSteerWire(core.stream, registry);
  const adapter = fakeAdapter(wire);
  const connection = yeahSteerConnection(adapter.connection, registry, [
    "prompt.message",
    STEER_CAPABILITY,
  ]);
  const events: ProviderEvent[] = [];
  connection.onEvent((event) => events.push(event));

  await connection.send(openSession("orch-1"));
  await connection.send(prompt("orch-1", "m-2", "steer", "остановись"));

  const result = events.find(
    (event) => event.type === "session.prompt_result" && event.clientMessageId === "m-2",
  );
  assert.ok(result && result.type === "session.prompt_result");
  assert.equal(result.result.type, "failed");
  const requests = core.received.filter(
    (message) => "method" in message && message.method === "session/steer",
  );
  assert.equal(requests.length, 0);
});

test("steering сессии, которой ядро не знает, — отказ", async () => {
  const registry = yeahSteerRegistry();
  const core = fakeCore();
  const wire = yeahSteerWire(core.stream, registry);
  const adapter = fakeAdapter(wire);
  const connection = yeahSteerConnection(adapter.connection, registry, [
    "prompt.message",
    STEER_CAPABILITY,
  ]);
  const events: ProviderEvent[] = [];
  connection.onEvent((event) => events.push(event));

  await connection.send(openSession("orch-1"));
  await connection.send(prompt("orch-1", "m-1", "auto", "работай"));
  await connection.send(prompt("orch-2", "m-2", "steer", "остановись"));

  const result = events.find(
    (event) => event.type === "session.prompt_result" && event.clientMessageId === "m-2",
  );
  assert.ok(result && result.type === "session.prompt_result");
  assert.equal(result.result.type, "failed");
});

test("текст steering — это текст сообщения", () => {
  assert.equal(
    yeahSteerText({
      clientMessageId: "m-1",
      delivery: "steer",
      input: { type: "message", content: [{ type: "text", text: "стоп" }] },
    }),
    "стоп",
  );
  assert.equal(
    yeahSteerText({
      clientMessageId: "m-1",
      delivery: "steer",
      input: { type: "command", name: "compact", arguments: "" },
    }),
    undefined,
  );
});
