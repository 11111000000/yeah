/**
 * Проверка ACP-сервера Yeah вручную: те же запросы, что шлёт Paseo.
 *
 * Скрипт поднимает сервер той же командой, которую регистрирует плагин,
 * и спрашивает его тем же протоколом: `initialize`, `session/new`,
 * `session/prompt`.  Ответы печатаются как есть.
 *
 *   npx tsx scripts/probe-acp.ts [текст запроса]
 */
import { spawn } from "node:child_process";
import path from "node:path";
import { readEnvFile, resolveEmacs, resolveGptelDir } from "../server/environment";
import { acpCommand, launchEnv, type YeahLaunch } from "../server/yeah";
import { repoPathFromEnv } from "../shared/paths";

const keyFile = `${process.env.HOME ?? "/home/az"}/.config/yeah/live.env`;
const values = readEnvFile(keyFile);
const launch: YeahLaunch = {
  emacs: resolveEmacs(),
  lib: path.join(repoPathFromEnv(), "lib"),
  gptel: resolveGptelDir(),
  model: values.YEAH_TEST_MODEL ?? "glm-5.3-flash",
  models: [values.YEAH_TEST_MODEL ?? "glm-5.3-flash"],
  host: values.YEAH_TEST_HOST ?? "api.z.ai",
  endpoint: "/api/v1/responses",
  profile: "build",
  dataHome: "",
};

const [executable, ...args] = acpCommand(launch);
const child = spawn(executable, [...args], {
  env: launchEnv(launch, values.YEAH_TEST_KEY ?? ""),
  stdio: ["pipe", "pipe", "pipe"],
});
child.stderr.on("data", (chunk: Buffer) => process.stderr.write(`[emacs] ${chunk}`));

let sessionId = "";
let buffer = "";
child.stdout.on("data", (chunk: Buffer) => {
  buffer += chunk.toString();
  const lines = buffer.split("\n");
  buffer = lines.pop() ?? "";
  for (const line of lines) {
    if (!line.trim()) continue;
    console.log(line);
    let message: { id?: number; result?: { sessionId?: string } };
    try {
      message = JSON.parse(line) as typeof message;
    } catch {
      continue;
    }
    if (message.id === 2 && message.result?.sessionId) {
      sessionId = message.result.sessionId;
      send({
        jsonrpc: "2.0",
        id: 3,
        method: "session/prompt",
        params: {
          sessionId,
          prompt: [
            {
              type: "text",
              text:
                process.argv[2] ??
                "Answer with the word OK and nothing else, then call the finish tool.",
            },
          ],
        },
      });
    }
  }
});
child.on("error", (error) => console.error(`[spawn] ${String(error)}`));

const send = (message: unknown): void => {
  child.stdin.write(`${JSON.stringify(message)}\n`);
};

send({
  jsonrpc: "2.0",
  id: 1,
  method: "initialize",
  params: {
    protocolVersion: 1,
    clientCapabilities: {},
    clientInfo: { name: "probe", version: "1" },
  },
});
send({
  jsonrpc: "2.0",
  id: 2,
  method: "session/new",
  params: { cwd: process.cwd(), mcpServers: [] },
});

setTimeout(() => {
  child.stdin.end();
  child.kill("SIGTERM");
}, 120000);
