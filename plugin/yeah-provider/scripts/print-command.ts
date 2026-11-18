/**
 * Печать команды запуска ACP-сервера Yeah: проверка вручную, без Paseo.
 *
 * Ключ в вывод не попадает: команда читает его из окружения, а значение
 * ключа печатается как «скрыто».
 */
import { readEnvFile, resolveEmacs, resolveGptelDir } from "../server/environment";
import { ENV, acpCommand, launchEnv, type YeahLaunch } from "../server/yeah";
import { repoPathFromEnv } from "../shared/paths";
import path from "node:path";

const keyFile = `${process.env.HOME ?? "/home/az"}/.config/yeah/live.env`;
const values = readEnvFile(keyFile);
const launch: YeahLaunch = {
  emacs: resolveEmacs(),
  lib: path.join(repoPathFromEnv(), "lib"),
  gptel: resolveGptelDir(),
  model: values.YEAH_TEST_MODEL ?? "MiniMax-M3.1-Flash",
  models: [values.YEAH_TEST_MODEL ?? "MiniMax-M3.1-Flash"],
  host: values.YEAH_TEST_HOST ?? "api.minimax.io",
  profile: "build",
  dataHome: "",
};
const env = launchEnv(launch, values.YEAH_TEST_KEY ?? "");
const shown = { ...env, [ENV.key]: env[ENV.key] ? "скрыто" : "" };
process.stdout.write(`${JSON.stringify({ command: acpCommand(launch), env: shown }, null, 2)}\n`);
