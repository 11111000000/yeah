/**
 * Запуск ACP-сервера Yeah: команда, окружение и формы.
 *
 * Всё живое форма берёт из окружения, а не из текста команды: путь к ядру,
 * каталог gptel, имя модели, хост и ключ приходят переменными `YEAH_ACP_*`.
 * Ключ провайдера в команду не попадает — он живёт в окружении процесса.
 *
 * Модуль ничего не знает про библиотеки: тут только то, что нужно, чтобы
 * поднять ядро.  Сервисный путь плагина (server/service.ts) берёт отсюда
 * команду сервиса и не тянет за собой ничего, что не работает без
 * установленных зависимостей.
 */
import path from "node:path";

/** Пути и параметры, из которых собирается запуск ACP-сервера Yeah. */
export interface YeahLaunch {
  /** Абсолютный путь к Emacs. */
  emacs: string;
  /** Каталог `lib` ядра Yeah. */
  lib: string;
  /** Каталог сборки gptel; пусто, если gptel на хосте нет. */
  gptel: string;
  /** Имя модели, на которой сервер стартует. */
  model: string;
  /** Имена всех моделей, на которых сервер может вести сессию. */
  models: readonly string[];
  /** Хост провайдера. */
  host: string;
  /** Эндпоинт провайдера. */
  endpoint: string;
  /** Профиль разрешений: `plan` запрещает, `build` спрашивает человека. */
  profile: "plan" | "build" | "auto";
  /** Каталог данных Yeah; пусто — умолчание ядра. */
  dataHome: string;
}

/** Имена переменных окружения, через которые ACP-сервер получает настройки. */
export const ENV = {
  lib: "YEAH_ACP_LIB",
  gptel: "YEAH_ACP_GPTEL",
  model: "YEAH_ACP_MODEL",
  models: "YEAH_ACP_MODELS",
  host: "YEAH_ACP_HOST",
  endpoint: "YEAH_ACP_ENDPOINT",
  key: "YEAH_ACP_KEY",
  profile: "YEAH_ACP_PROFILE",
  dataHome: "YEAH_ACP_DATA_HOME",
  /** Путь сокета, на котором сервис слушает ACP. */
  socket: "YEAH_ACP_SOCKET",
} as const;

/**
 * Форма запуска Emacs.
 *
 * Порядок важен: сначала путь поиска модулей, потом gptel и бэкенд модели,
 * потом ядро Yeah и профиль разрешений, и только потом сервер ACP.
 *
 * Пустая переменная окружения — это отсутствие значения, а не значение:
 * пустой каталог в `load-path` и пустой каталог данных ломают ядро.
 *
 * Бэкенд модели знает все модели, на которых сервер может вести сессию:
 * модель сессии меняется по проводу, и gptel берёт только ту модель, которую
 * знает его бэкенд.  Поэтому список моделей — это то, что бэкенд принял, а
 * не одна модель запуска.
 */
/**
 * Настройка ядра в процессе сервера: путь поиска модулей, gptel и бэкенд
 * модели, профиль прав.
 *
 * Настройка одна и та же для обоих размещений: и для сервера на stdio, и для
 * сервиса на сокете.  Различается только последняя строка формы — куда
 * сервер слушает.
 */
const CORE_SETUP = `  (dolist (dir (list (getenv "${ENV.lib}") (getenv "${ENV.gptel}")))
    (when (and dir (not (string-empty-p dir)))
      (add-to-list 'load-path dir)))
  (let ((home (getenv "${ENV.dataHome}")))
    (when (and home (not (string-empty-p home)))
      (setq yeah-data-home home)))
  (require 'gptel)
  (require 'gptel-openai)
  (require 'gptel-openai-responses)
  (let ((model (getenv "${ENV.model}"))
        (host (getenv "${ENV.host}"))
        (endpoint (getenv "${ENV.endpoint}"))
        (profile (getenv "${ENV.profile}"))
        (key (getenv "${ENV.key}"))
        (names (let ((raw (getenv "${ENV.models}")))
                 (let ((split (if (and raw (not (string-empty-p raw)))
                                  (split-string raw "," t "[ \\t]+")
                                nil)))
                   (if split
                       split
                     (list "glm-5.3-flash"))))))
    (setq gptel-backend
          (let ((api-host (if (and host (not (string-empty-p host))) host "api.z.ai"))
                (api-endpoint (if (and endpoint (not (string-empty-p endpoint)))
                                  endpoint
                                "/api/v1/responses")))
            (if (string-match-p "responses" api-endpoint)
                (gptel-make-openai-responses "paseo"
                  :host api-host
                  :endpoint api-endpoint
                  :key key
                  :models (mapcar #'intern names))
              (gptel-make-openai "paseo"
                :host api-host
                :endpoint api-endpoint
                :key key
                :models (mapcar #'intern names)))))
    (setq gptel-model
          (intern (if (and model (not (string-empty-p model)))
                     model
                   (car names))))
    (require 'yeah-perm)
    (require 'yeah-acp)
    (dolist (rule (yeah-perm-profile (if (and profile (not (string-empty-p profile)))
                                         profile "build")))
      (yeah-perm-rules-add rule)))
`;

export const LAUNCH_FORM = `(progn${CORE_SETUP}
  (yeah-acp-serve))`;

/**
 * Форма запуска сервиса: тот же бэкенд модели, но сервер слушает сокет.
 *
 * Путь сокета приходит в окружении: имя сокета — это имя сервиса, и плагин
 * знает его раньше, чем сервис поднимется.  Жизнь сервиса — это сокет жизни
 * хозяина: сервис смотрит на него и заканчивается, когда хозяин уходит.
 */
export const SERVICE_FORM = `(progn${CORE_SETUP}
  (yeah-acp-serve-socket (getenv "${ENV.socket}") nil nil 'local nil))`;

/** Команда запуска ACP-сервера: Emacs в пакетном режиме и форма выше. */
export function acpCommand(launch: YeahLaunch): readonly [string, ...string[]] {
  return [launch.emacs, "-Q", "--batch", "--eval", LAUNCH_FORM];
}

/** Команда запуска сервиса: Emacs в пакетном режиме и форма сервиса. */
export function serviceCommand(launch: YeahLaunch): readonly [string, ...string[]] {
  return [launch.emacs, "-Q", "--batch", "--eval", SERVICE_FORM];
}

/**
 * Окружение процесса ACP.
 *
 * За основу берётся окружение плагина, а поверх него — переменные запуска
 * ядра. Ключ провайдера попадает сюда из файла вне дерева репозитория и в
 * настройки плагина не попадает: значение не печатается и не сохраняется.
 *
 * В `PATH` добавляется каталог Emacs: окружение демона не содержит профиля
 * Nix, а ядру нужен `bash` и `git` рядом с Emacs.
 */
export function launchEnv(
  launch: YeahLaunch,
  key: string,
  base: NodeJS.ProcessEnv = process.env,
): Record<string, string> {
  const env: Record<string, string> = {};
  for (const [name, value] of Object.entries(base)) {
    if (typeof value === "string") env[name] = value;
  }
  env[ENV.lib] = launch.lib;
  env[ENV.gptel] = launch.gptel;
  env[ENV.model] = launch.model;
  env[ENV.models] = launch.models.join(",");
  env[ENV.host] = launch.host;
  env[ENV.endpoint] = launch.endpoint;
  env[ENV.key] = key;
  env[ENV.profile] = launch.profile;
  env[ENV.dataHome] = launch.dataHome;
  const emacsDir = path.dirname(launch.emacs);
  const currentPath = env.PATH ?? "";
  env.PATH = currentPath
    .split(path.delimiter)
    .filter((entry) => entry && entry !== emacsDir)
    .join(path.delimiter);
  env.PATH = [emacsDir, env.PATH].filter(Boolean).join(path.delimiter);
  return env;
}
