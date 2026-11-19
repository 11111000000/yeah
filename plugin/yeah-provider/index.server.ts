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
import { yeahCatalog } from "./server/catalog";
import {
  yeahOutcomeNotification,
  yeahToolCallTransformer,
  type YeahLaunch,
} from "./server/yeah";
import { yeahTransport, type YeahPlacement } from "./server/transport";
import {
  yeahSteerConnection,
  yeahSteerRegistry,
  yeahSteerWire,
} from "./server/steer";
import type { YeahService } from "./server/service";
import {
  yeahUsageConnection,
  yeahUsageNotification,
  yeahUsageRegistry,
} from "./server/usage";
import { yeahModelsOf, yeahSettings, type YeahSettingsValues } from "./shared/settings";
import { repoPathFromEnv } from "./shared/paths";

/** Настройки по умолчанию: те же значения, что в схеме настроек. */
const DEFAULTS: YeahSettingsValues = {
  repoPath: repoPathFromEnv(),
  gptelPath: "",
  emacsPath: "",
  model: "MiniMax-M3.1-Flash",
  models: "",
  host: "api.minimax.io",
  profile: "build",
  keyFile: "~/.config/yeah/live.env",
  dataHome: "",
  serviceMode: "spawn",
  serviceName: "paseo",
};

/** Собрать запуск ACP-сервера из настроек. */
export function launchOf(values: YeahSettingsValues): YeahLaunch {
  const repo = expandHome(values.repoPath);
  return {
    emacs: resolveEmacs(values.emacsPath),
    lib: path.join(repo, "lib"),
    gptel: resolveGptelDir(values.gptelPath),
    model: values.model,
    models: yeahModelsOf(values),
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

  // Реестр steering: сессия оркестратора и сессия ядра — это разные
  // идентификаторы, и плагин сопоставляет их по проводу.
  const steer = yeahSteerRegistry();

  // Реестр расхода хода: уведомление ядра приходит без указания сессии, а
  // событие провайдера без сессии некуда положить.  Реестр сопоставляет их.
  const usage = yeahUsageRegistry();

  // Сервис ядра, если выбрано сервисное размещение.  Он один на плагин:
  // сессии приходят к нему по очереди, и плагин помнит, к какому сокету
  // идти.  Размещение по умолчанию — свой Emacs на соединение, и тогда
  // сервиса нет.
  let service: YeahService | null = null;

  const provider = runAcpProvider({
    id: "yeah",
    label: "Yeah",
    description:
      "The Yeah kernel: an Emacs Lisp agent harness that runs inside Emacs",
    // Соединитель, а не команда: процесс ACP поднимает плагин, и его
    // окружение (путь к ядру, gptel и ключ) доезжает до Emacs целиком.
    connector: async () => {
      await firstRead.catch(() => undefined);
      const launch = launchOf(values);
      const transport = await yeahTransport({
        launch,
        key: keyOf(values),
        mode: values.serviceMode as YeahPlacement,
        serviceName: values.serviceName,
        service,
      });
      // Сервис один на плагин: следующий агент приходит к тому же Emacs, и его
      // соединение не стоит ничего, кроме сокета.
      service = transport.service;
      // Провод обёрнут: плагин видит, какую сессию ядро открыло, и может
      // слать в ядро `session/steer` мимо адаптера.
      return yeahSteerWire(transport.stream, steer);
    },
    transformers: [
      { toolCall: yeahToolCallTransformer },
      {
        // Исход прогона — словарь ядра, а не ACP: ядро шлёт его
        // уведомлением `yeah/outcome` только тем, кто объявил
        // `yeah.runOutcome` в `_meta` возможностей клиента. Оркестратор
        // такого метода не знает, поэтому плагин переводит исход в
        // уведомление, которое оркестратор показывает.
        notification: yeahOutcomeNotification,
      },
      {
        // Расход хода — тоже словарь ядра: ядро шлёт его уведомлением
        // `yeah/usage` тем, кто объявил `yeah.usage`. Соединитель
        // оркестратора выбрасывает ответ на `session/prompt` вместе с
        // полем `usage`, поэтому плагин берёт расход из уведомления и
        // отдаёт его событием `session.usage` — тем, что оркестратор
        // переносит в расход агента.
        notification: yeahUsageNotification(usage),
      },
      {
        // Модель сессии меняет ядро: оно публикует модели в ответе
        // `session/new` и меняет модель через `session/set_config_option`.
        // Плагин публикует каталог моделей, которые знает его бэкенд, и
        // не перехватывает смену модели -- запрос уходит в ядро.
        discover: (catalog) => yeahCatalog(catalog, yeahModelsOf(values)),
      },
    ],
  });

  server.registerProvider({
    ...provider,
    // Соединение обёрнуто: события соединения идут дальше как есть, а
    // расход хода добавляется к ним -- оркестратор считает токены хода
    // только по событию `session.usage`.  Снаружи -- steering: запрос,
    // пришедший посреди хода, доходит до ядра как уточнение, а не как новый
    // ход, и возможность steering объявляется, только когда оркестратор её
    // предложил.
    connect: async (request) =>
      yeahSteerConnection(
        yeahUsageConnection(await provider.connect(request), usage),
        steer,
        request.capabilities,
      ),
  });

  return () => {
    delete process.env.YEAH_ACP_KEY;
    // Плагин уходит — сервис уходит с ним: сервис без хозяина ждёт клиента,
    // который не придёт.
    void service?.close();
    service = null;
  };
}
