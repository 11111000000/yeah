/**
 * Разбор соединителя: поднимает поддельного агента и читает ответ.
 * Скрипт для отладки, не часть тестов.
 */
import path from "node:path";
import { acpStream } from "../server/yeah";

const here = __dirname;
const fixture = path.join(here, "..", "test", "fixtures", "fake-acp-agent.mjs");

async function main(): Promise<void> {
const stream = acpStream([process.execPath, fixture], {
  ...process.env,
  PROBE_MARKER: "доставлено",
});
const writer = stream.writable.getWriter();
const reader = stream.readable.getReader();
console.log("write…");
await writer.write({
  jsonrpc: "2.0",
  id: 1,
  method: "initialize",
  params: { protocolVersion: 1, clientCapabilities: {} },
});
console.log("read…");
const answer = await reader.read();
console.log("answer:", JSON.stringify(answer));
console.log("close…");
await writer.close();
console.log("closed");
}

main().then(
  () => {
    console.log("ждём естественного выхода процесса…");
    setTimeout(() => {
      console.log("процесс всё ещё жив — нужен kill");
      process.exit(3);
    }, 3000).unref();
  },
  (error: unknown) => {
    console.error(String(error));
    process.exit(1);
  },
);
