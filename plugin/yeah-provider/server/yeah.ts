/**
 * Сборка запуска ACP-сервера Yeah: команда, окружение и поток провода.
 *
 * ACP-сервер Yeah говорит по проводу JSON-RPC и живёт в Emacs: команда
 * запускает Emacs в пакетном режиме, а форма запуска настраивает модель
 * через gptel. Всё живое форма берёт из окружения, а не из текста команды.
 *
 * Процесс поднимает сам плагин, а не демон Paseo. Это не выбор вкуса:
 * демон запускает провайдера своим окружением и переменные `YEAH_ACP_*` в
 * нём не знают, поэтому ядро не находит ни gptel, ни ключ. Соединитель
 * плагина (`connector`) отдаёт демону поток провода и отвечает за процесс.
 */
import { spawnProcess } from "@getpaseo/plugin/server";
import type { AcpStream, AcpToolCallSnapshot } from "@getpaseo/plugin/server/acp";
import { ndJsonStream } from "@agentclientprotocol/sdk";
import { Readable, Writable } from "node:stream";
import path from "node:path";

/** Пути и параметры, из которых собирается запуск ACP-сервера Yeah. */
export interface YeahLaunch {
  /** Абсолютный путь к Emacs. */
  emacs: string;
  /** Каталог `lib` ядра Yeah. */
  lib: string;
  /** Каталог сборки gptel; пусто, если gptel на хосте нет. */
  gptel: string;
  /** Имя модели. */
  model: string;
  /** Хост провайдера. */
  host: string;
  /** Профиль разрешений: `plan` запрещает, `build` спрашивает человека. */
  profile: "plan" | "build";
  /** Каталог данных Yeah; пусто — умолчание ядра. */
  dataHome: string;
}

/** Имена переменных окружения, через которые ACP-сервер получает настройки. */
export const ENV = {
  lib: "YEAH_ACP_LIB",
  gptel: "YEAH_ACP_GPTEL",
  model: "YEAH_ACP_MODEL",
  host: "YEAH_ACP_HOST",
  key: "YEAH_ACP_KEY",
  profile: "YEAH_ACP_PROFILE",
  dataHome: "YEAH_ACP_DATA_HOME",
} as const;

/**
 * Форма запуска Emacs.
 *
 * Порядок важен: сначала путь поиска модулей, потом gptel и бэкенд модели,
 * потом ядро Yeah и профиль разрешений, и только потом сервер ACP.
 *
 * Пустая переменная окружения — это отсутствие значения, а не значение:
 * пустой каталог в `load-path` и пустой каталог данных ломают ядро.
 */
export const LAUNCH_FORM = `(progn
  (dolist (dir (list (getenv "${ENV.lib}") (getenv "${ENV.gptel}")))
    (when (and dir (not (string-empty-p dir)))
      (add-to-list 'load-path dir)))
  (let ((home (getenv "${ENV.dataHome}")))
    (when (and home (not (string-empty-p home)))
      (setq yeah-data-home home)))
  (require 'gptel)
  (require 'gptel-openai)
  (let ((model (getenv "${ENV.model}"))
        (host (getenv "${ENV.host}"))
        (profile (getenv "${ENV.profile}"))
        (key (getenv "${ENV.key}")))
    (setq gptel-backend
          (gptel-make-openai "paseo"
            :host (if (and host (not (string-empty-p host))) host "api.minimax.io")
            :endpoint "/v1/chat/completions"
            :key key
            :models (list (intern (if (and model (not (string-empty-p model)))
                                     model "MiniMax-M3.1-Flash")))))
    (setq gptel-model
          (intern (if (and model (not (string-empty-p model)))
                     model "MiniMax-M3.1-Flash")))
    (require 'yeah-perm)
    (require 'yeah-acp)
    (dolist (rule (yeah-perm-profile (if (and profile (not (string-empty-p profile)))
                                         profile "build")))
      (yeah-perm-rules-add rule)))
  (yeah-acp-serve))`;

/** Команда запуска ACP-сервера: Emacs в пакетном режиме и форма выше. */
export function acpCommand(launch: YeahLaunch): readonly [string, ...string[]] {
  return [launch.emacs, "-Q", "--batch", "--eval", LAUNCH_FORM];
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
  env[ENV.host] = launch.host;
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

/**
 * Поднять процесс ACP-сервера и вернуть поток провода.
 *
 * Поток — тот же формат JSON-RPC по строкам, что и у демона Paseo, только
 * процессом управляет плагин: так до Emacs доезжает окружение плагина.
 * Ошибка процесса видна в журнале плагина, а не теряется в молчании.
 *
 * Поток из SDK не закрывает stdin процесса: без этого Emacs ждал бы
 * данных вечно, а тест — ребёнка. Поэтому закрытие потока закрывает stdin,
 * и процесс уходит по EOF.
 */
export function acpStream(
  command: readonly [string, ...string[]],
  env: NodeJS.ProcessEnv,
): AcpStream {
  const [executable, ...args] = command;
  const child = spawnProcess(executable, args, { env, stdio: "pipe" });
  child.stderr.on("data", (chunk: Buffer) => {
    const text = String(chunk).trimEnd();
    if (text) console.log(`[yeah] ACP stderr: ${text}`);
  });
  child.on("exit", (code, signal) => {
    console.log(`[yeah] ACP процесс завершился: код ${code}, сигнал ${signal}`);
  });

  const sdk = ndJsonStream(Writable.toWeb(child.stdin), Readable.toWeb(child.stdout));
  const writer = sdk.writable.getWriter();
  const reader = sdk.readable.getReader();

  const endInput = (): void => {
    if (!child.stdin.destroyed) child.stdin.end();
  };

  const stream: AcpStream = {
    writable: new WritableStream({
      async write(message) {
        await writer.write(message as never);
      },
      async close() {
        await writer.close().catch(() => undefined);
        endInput();
      },
      async abort(reason) {
        await writer.abort(reason).catch(() => undefined);
        endInput();
      },
    }),
    readable: new ReadableStream({
      async pull(controller) {
        try {
          const next = await reader.read();
          if (next.done) {
            controller.close();
            endInput();
          } else {
            controller.enqueue(next.value as never);
          }
        } catch (error) {
          controller.error(error);
          endInput();
        }
      },
      cancel(reason) {
        void reader.cancel(reason).catch(() => undefined);
        endInput();
      },
    }),
  };
  return stream;
}

/**
 * Род вызова инструмента по его имени.
 *
 * Ядро Yeah шлёт в обновлении род вызова сам: род — это факт инструмента,
 * а не догадка по его названию. Таблица остаётся запасным путём для ядра,
 * которое род ещё не шлёт: провод — источник истины, и род, который в
 * проводе есть, не меняется.
 */
const TOOL_KINDS: Record<string, string> = {
  read: "read",
  glob: "search",
  grep: "search",
  edit: "edit",
  write: "edit",
  bash: "execute",
  "elisp-check": "execute",
  job: "execute",
  finish: "other",
};

/**
 * Имена аргументов правки, как их читает клиент Paseo.
 *
 * Ядро шлёт именованные аргументы под именами, которые объявил инструмент:
 * `path`, `old_str`, `new_str`. Клиент Paseo рисует правку по полям
 * `filePath`, `oldString` и `newString`, и без них он рисует вызов без
 * правки. Перевод имён — работа плагина: это соглашение Paseo, а не
 * соглашение ядра, и ядро его не знает.
 */
const EDIT_ARGUMENT_NAMES: Record<string, string> = {
  path: "filePath",
  old_str: "oldString",
  new_str: "newString",
};

/** Имя инструмента в снимке: ядро шлёт его в заголовке. */
export function toolNameOf(toolCall: AcpToolCallSnapshot): string {
  const candidates = [toolCall.name, toolCall.title];
  for (const candidate of candidates) {
    if (typeof candidate === "string" && candidate) return candidate;
  }
  return "";
}

/**
 * Имена аргументов правки в том виде, в каком их читает клиент Paseo.
 *
 * Вызов, который не является правкой, и вызов без аргументов остаются как
 * есть: перевод меняет только имена полей правки и ничего больше.
 */
export function yeahEditArguments(
  toolCall: AcpToolCallSnapshot,
): AcpToolCallSnapshot["input"] {
  const input = toolCall.input as unknown;
  if (typeof input !== "object" || input === null || Array.isArray(input)) {
    return toolCall.input;
  }
  const kind = toolCall.kind ?? TOOL_KINDS[toolNameOf(toolCall)];
  if (kind !== "edit") return toolCall.input;
  const source = input as Record<string, unknown>;
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(source)) {
    result[EDIT_ARGUMENT_NAMES[key] ?? key] = value;
  }
  return result as AcpToolCallSnapshot["input"];
}

/**
 * Дополнить вызов инструмента родом и именами его аргументов.
 *
 * Снимок, у которого род уже есть, не меняется: провод — источник истины,
 * плагин только добавляет то, чего в проводе нет. Имена аргументов
 * переводятся всегда: это соглашение клиента, и провод его не меняет.
 */
export function yeahToolCallTransformer(
  toolCall: AcpToolCallSnapshot,
): AcpToolCallSnapshot {
  const withKind = toolCall.kind
    ? toolCall
    : (() => {
        const kind = TOOL_KINDS[toolNameOf(toolCall)];
        return kind ? { ...toolCall, kind } : toolCall;
      })();
  const input = yeahEditArguments(withKind);
  return input === withKind.input ? withKind : { ...withKind, input };
}
