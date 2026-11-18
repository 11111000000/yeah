/**
 * Поддельный ACP-агент для офлайн-проверки соединителя плагина.
 *
 * Говорит по проводу JSON-RPC по строкам: отвечает на `initialize` и
 * возвращает в ответе значение переменной окружения `PROBE_MARKER`, чтобы
 * проверка видела, что окружение доехало до процесса.
 */
import { createInterface } from "node:readline";

const reader = createInterface({ input: process.stdin });
reader.on("line", (line) => {
  const text = line.trim();
  if (!text) return;
  let message;
  try {
    message = JSON.parse(text);
  } catch {
    return;
  }
  if (message.id === undefined) return;
  const result =
    message.method === "initialize"
      ? {
          protocolVersion: 1,
          agentInfo: { name: "fake", version: "0.0.0" },
          agentCapabilities: {},
          marker: process.env.PROBE_MARKER ?? "",
        }
      : { marker: process.env.PROBE_MARKER ?? "" };
  process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id: message.id, result })}\n`);
});
