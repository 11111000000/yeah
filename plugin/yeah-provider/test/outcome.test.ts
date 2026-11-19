import assert from "node:assert/strict";
import path from "node:path";
import { test } from "node:test";
import type { AcpStreamMessage } from "@getpaseo/plugin/server/acp";
import {
  OUTCOME_METHOD,
  RUN_OUTCOME_KEY,
  acpStream,
  yeahInitializeRequest,
  yeahOutcomeNotification,
} from "../server/yeah";

const here = __dirname;

/**
 * Сообщение как запрос.
 *
 * Провод — это союз форм, и у ответа нет ни метода, ни параметров. Проверка
 * хочет знать, что запрос не потерял ни своего вида, ни своих полей, и
 * разбирает союз здесь, а не через приведение типа.
 */
function asRequest(message: AcpStreamMessage): {
  id?: string | number | null;
  method?: string;
  params: Record<string, unknown>;
} {
  const params = "params" in message ? message.params : undefined;
  return {
    id: "id" in message ? message.id : undefined,
    method: "method" in message ? message.method : undefined,
    params: (params ?? {}) as Record<string, unknown>,
  };
}

test("исход прогона переводится в уведомление оркестратора", () => {
  const update = yeahOutcomeNotification({
    method: OUTCOME_METHOD,
    params: {
      sessionId: "session-1-abc",
      outcome: "nudge",
      payload: "модель молчала, подтолкнуть её",
    },
  });
  assert.deepEqual(update, {
    type: "notice",
    notice: {
      id: "yeah-nudge-session-1-abc",
      severity: "info",
      title: "Агент подтолкнут",
      description: "модель молчала, подтолкнуть её",
    },
  });
});

test("прогон без результата — предупреждение, а упавший прогон — ошибка", () => {
  const unfinished = yeahOutcomeNotification({
    method: OUTCOME_METHOD,
    params: { sessionId: "s-1", outcome: "unfinished", payload: "нет эффекта" },
  });
  const failed = yeahOutcomeNotification({
    method: OUTCOME_METHOD,
    params: { sessionId: "s-1", outcome: "error", payload: "провайдер отказал" },
  });
  assert.equal(
    (unfinished as { notice: { severity: string } }).notice.severity,
    "warning",
  );
  assert.equal(
    (unfinished as { notice: { title: string } }).notice.title,
    "Прогон закончился без результата",
  );
  assert.equal((failed as { notice: { severity: string } }).notice.severity, "error");
  assert.equal((failed as { notice: { title: string } }).notice.title, "Прогон упал");
});

test("описание уведомления — payload, а reason приходит вторым", () => {
  const update = yeahOutcomeNotification({
    method: OUTCOME_METHOD,
    params: {
      sessionId: "s-2",
      outcome: "unfinished",
      payload: "ответ без эффекта",
      reason: "бюджет подталкиваний исчерпан",
    },
  });
  assert.equal(
    (update as { notice: { description: string } }).notice.description,
    "ответ без эффекта",
  );
});

test("уведомление без payload берёт reason", () => {
  const update = yeahOutcomeNotification({
    method: OUTCOME_METHOD,
    params: {
      sessionId: "s-3",
      outcome: "unfinished",
      reason: "бюджет подталкиваний исчерпан",
    },
  });
  assert.equal(
    (update as { notice: { description: string } }).notice.description,
    "бюджет подталкиваний исчерпан",
  );
});

test("уведомление без payload и reason не имеет описания", () => {
  const update = yeahOutcomeNotification({
    method: OUTCOME_METHOD,
    params: { sessionId: "s-4", outcome: "nudge" },
  });
  assert.deepEqual(update, {
    type: "notice",
    notice: {
      id: "yeah-nudge-s-4",
      severity: "info",
      title: "Агент подтолкнут",
    },
  });
});

test("уведомление с чужим методом игнорируется", () => {
  assert.equal(
    yeahOutcomeNotification({
      method: "session/update",
      params: { sessionId: "s-5", outcome: "nudge" },
    }),
    null,
  );
});

test("запрос initialize объявляет клиенту исход прогона", () => {
  const request = asRequest(
    yeahInitializeRequest({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: 1,
        clientCapabilities: { fs: { readTextFile: true } },
        clientInfo: { name: "paseo", version: "1" },
      },
    }),
  );
  const capabilities = request.params.clientCapabilities as {
    _meta: Record<string, unknown>;
    fs: unknown;
  };
  assert.equal(capabilities._meta[RUN_OUTCOME_KEY], true);
  // Объявление дополняет возможности, а не заменяет их.
  assert.deepEqual(capabilities.fs, { readTextFile: true });
  assert.equal(request.params.protocolVersion, 1);
  assert.deepEqual(request.params.clientInfo, { name: "paseo", version: "1" });
  assert.equal(request.id, 1);
  assert.equal(request.method, "initialize");
});

test("запрос initialize без clientCapabilities получает объявление", () => {
  const request = asRequest(
    yeahInitializeRequest({
      jsonrpc: "2.0",
      id: 2,
      method: "initialize",
      params: { protocolVersion: 1 },
    }),
  );
  const capabilities = request.params.clientCapabilities as {
    _meta: Record<string, unknown>;
  };
  assert.equal(capabilities._meta[RUN_OUTCOME_KEY], true);
});

test("чужая `_meta` в возможностях клиента не теряется", () => {
  const request = asRequest(
    yeahInitializeRequest({
      jsonrpc: "2.0",
      id: 3,
      method: "initialize",
      params: {
        clientCapabilities: { _meta: { "yeah.queueEvents": true } },
      },
    }),
  );
  const capabilities = request.params.clientCapabilities as {
    _meta: Record<string, unknown>;
  };
  assert.equal(capabilities._meta["yeah.queueEvents"], true);
  assert.equal(capabilities._meta[RUN_OUTCOME_KEY], true);
});

test("запрос с другим методом не меняется", () => {
  const request = asRequest(
    yeahInitializeRequest({
      jsonrpc: "2.0",
      id: 4,
      method: "session/new",
      params: { cwd: "/tmp", mcpServers: [] },
    }),
  );
  assert.deepEqual(request.params, { cwd: "/tmp", mcpServers: [] });
});

test("нотификация initialize — не запрос и не переписывается", () => {
  const request = asRequest(
    yeahInitializeRequest({
      jsonrpc: "2.0",
      method: "initialize",
      params: { clientCapabilities: {} },
    }),
  );
  assert.deepEqual(request.params, { clientCapabilities: {} });
});

test("поток провода дополняет запрос initialize на пути к ядру", async () => {
  // Проверка чистой функции не видит провода: объявление должно доехать до
  // процесса тем же путём, каким идёт запрос демона оркестратора.
  const stream = acpStream(
    [process.execPath, path.join(here, "fixtures", "fake-acp-agent.mjs")],
    { ...process.env },
  );
  const writer = stream.writable.getWriter();
  const reader = stream.readable.getReader();
  try {
    await writer.write({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: { protocolVersion: 1, clientCapabilities: { fs: { readTextFile: true } } },
    });
    const answer = await reader.read();
    assert.equal(answer.done, false);
    const message = answer.value as {
      result?: { clientCapabilities?: { _meta?: Record<string, unknown>; fs?: unknown } };
    };
    assert.equal(message.result?.clientCapabilities?._meta?.[RUN_OUTCOME_KEY], true);
    assert.deepEqual(message.result?.clientCapabilities?.fs, { readTextFile: true });
  } finally {
    // Процесс закрывается в любом случае: упавшая проверка не должна
    // оставлять ребёнка живым и заставлять прогон ждать.
    await writer.close().catch(() => undefined);
  }
});
