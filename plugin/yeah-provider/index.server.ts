/**
 * Плагин Paseo: агент Yeah.
 *
 * Плагин регистрирует провайдера ACP, который поднимает ACP-сервер ядра
 * Yeah в Emacs и говорит с ним по проводу JSON-RPC. Человек выбирает агента
 * в Paseo так же, как любого другого: провайдер появляется в списке.
 *
 * Ключ провайдера в настройках не хранится: он лежит в файле окружения вне
 * дерева репозитория, и плагин только читает его оттуда.
 */
import type { PluginServerContext } from "@getpaseo/plugin/server";
import { runAcpProvider } from "@getpaseo/plugin/server/acp";
import path from "node:path";
import {
  expandHome,
  readEnvFile,
  resolveEmacs,
  resolveGptelDir,
} from "./server/environment";
import { yeahCatalog, yeahConfigure } from "./server/catalog";
import {
  acpCommand,
  acpStream,
  launchEnv,
  yeahToolCallTransformer,
  type YeahLaunch,
} from "./server/yeah";
import { yeahSettings, type YeahSettingsValues } from "./shared/settings";
import { repoPathFromEnv } from "./shared/paths";

/** Настройки по умолчанию: те же значения, что в схеме настроек. */
const DEFAULTS: YeahSettingsValues = {
  repoPath: repoPathFromEnv(),
  gptelPath: "",
  emacsPath: "",
  model: "MiniMax-M3.1-Flash",
  host: "api.minimax.io",
  profile: "build",
  keyFile: "~/.config/yeah/live.env",
  dataHome: "",
};

/** Собрать запуск ACP-сервера из настроек. */
export function launchOf(values: YeahSettingsValues): YeahLaunch {
  const repo = expandHome(values.repoPath);
  return {
    emacs: resolveEmacs(values.emacsPath),
    lib: path.join(repo, "lib"),
    gptel: resolveGptelDir(values.gptelPath),
    model: values.model,
    host: values.host,
    profile: values.profile,
    dataHome: values.dataHome ? expandHome(values.dataHome) : "",
  };
}

/**
 * Ключ провайдера: сначала окружение демона, потом файл вне репозитория.
 * Значение не возвращается наружу и не печатается.
 */
export function keyOf(values: YeahSettingsValues): string {
  const fromEnv = process.env.YEAH_ACP_KEY ?? "";
  if (fromEnv) return fromEnv;
  const file = readEnvFile(expandHome(values.keyFile));
  return file.YEAH_ACP_KEY ?? file.YEAH_TEST_KEY ?? "";
}

export default function contribute(server: PluginServerContext) {
  const settings = server.registerSettings(yeahSettings);

  // Настройки читаются один раз и обновляются подпиской; процесс ACP
  // поднимается в момент подключения, поэтому он видит текущие значения и
  // перезапуск плагина не нужен.
  let values: YeahSettingsValues = DEFAULTS;
  const firstRead = settings.read();

  const apply = (next: YeahSettingsValues): void => {
    values = next;
    if (!keyOf(next)) {
      console.log(
        "[yeah] ключ провайдера не найден: " +
          "проверьте файл окружения из настроек (YEAH_ACP_KEY или YEAH_TEST_KEY)",
      );
    }
  };

  firstRead
    .then((state) => {
      if (state.status === "ready") apply(state.values);
      else console.log(`[yeah] настройки не прочитаны: ${state.error}`);
    })
    .catch((error: unknown) => {
      console.log(`[yeah] настройки не прочитаны: ${String(error)}`);
    });

  settings.subscribe((state) => {
    if (state.status === "ready") apply(state.values);
  });

  server.registerProvider(
    runAcpProvider({
      id: "yeah",
      label: "Yeah",
      description:
        "The Yeah kernel: an Emacs Lisp agent harness that runs inside Emacs",
      // Соединитель, а не команда: процесс ACP поднимает плагин, и его
      // окружение (путь к ядру, gptel и ключ) доезжает до Emacs целиком.
      connector: async () => {
        await firstRead.catch(() => undefined);
        const launch = launchOf(values);
        return acpStream(acpCommand(launch), launchEnv(launch, keyOf(values)));
      },
      transformers: [
        { toolCall: yeahToolCallTransformer },
        {
          // Ядро не публикует модель по проводу: каталог и смена модели
          // — работа плагина, и модель там одна, та, что задана настройкой.
          discover: (catalog) => yeahCatalog(catalog, values.model),
          configure: (change) => yeahConfigure(change, values.model),
        },
      ],
    }),
  );

  return () => {
    delete process.env.YEAH_ACP_KEY;
  };
}
