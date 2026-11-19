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
import type {
  AcpStream,
  AcpToolCallSnapshot,
  AcpVendorUpdate,
} from "@getpaseo/plugin/server/acp";
import type { ProviderNotice } from "@getpaseo/plugin/server/provider";
import { ndJsonStream } from "@agentclientprotocol/sdk";
import { Readable, Writable } from "node:stream";
import path from "node:path";
import {
  OUTCOME_METHOD,
  RUN_OUTCOME_KEY,
  USAGE_KEY,
  asRecord,
  yeahInitializeRequest,
} from "../shared/vocabulary";

// Запуск живёт в своём модуле: его читает и процессный путь плагина, и
// сервисный.  Здесь оно только переэкспортируется — те, кто знает плагин по
// прежним именам, продолжают знать его по прежним именам.
export {
  ENV,
  LAUNCH_FORM,
  SERVICE_FORM,
  acpCommand,
  serviceCommand,
  launchEnv,
} from "./launch";
export type { YeahLaunch } from "./launch";

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
        // Запрос `initialize` идёт от демона оркестратора, и в нём нет
        // ничего о словаре Yeah: плагин дополняет его на пути к ядру.
        await writer.write(yeahInitializeRequest(message) as never);
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

/**
 * Метод уведомления ядра, которое несёт исход прогона.
 *
 * Исход прогона — словарь самого Yeah: подталкивание, вытолкнувшее модель,
 * прогон, закончившийся без эффекта, и ошибка, которая его остановила. В ACP
 * такого метода нет, а клиент, который его не знает, отверг бы обновление
 * целиком. Поэтому исход едет к оркестратору только через плагин, который
 * переводит его в то, что оркестратор показывает.
 */
// Словарь Yeah живёт в своём модуле: его читает и процессный путь, и
// сервисный.  Здесь оно только переэкспортируется — те, кто знает плагин по
// прежним именам, продолжают знать его по прежним именам.
export { OUTCOME_METHOD, RUN_OUTCOME_KEY, yeahInitializeRequest };

/** Как исход прогона выглядит в интерфейсе оркестратора. */
interface OutcomeNotice {
  severity: "info" | "warning" | "error";
  title: string;
}

/**
 * Исходы прогона и то, как оркестратор их показывает.
 *
 * Серьёзность отвечает на вопрос человека «надо ли мне вмешиваться»: ошибка
 * прогона — надо, прогон без результата — стоит знать, а подталкивание — это
 * фон, о котором человек знать не обязан.
 */
const OUTCOME_NOTICES: Record<string, OutcomeNotice | undefined> = {
  nudge: { severity: "info", title: "Агент подтолкнут" },
  unfinished: { severity: "warning", title: "Прогон закончился без результата" },
  error: { severity: "error", title: "Прогон упал" },
};


/** Текст поля, если оно есть и не пустое. */
function textOf(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

/**
 * Перевести уведомление ядра об исходе прогона в уведомление оркестратора.
 *
 * Уведомление с чужим методом — не наше: возвращается `null`, и оркестратор
 * не получает ничего. Исход, которого ядро ещё не знает, показывается как
 * событие прогона: лучше тихое уведомление, чем уведомление с чужой
 * серьёзностью.
 */
export function yeahOutcomeNotification(notification: {
  method: string;
  params: unknown;
}): AcpVendorUpdate | null {
  if (notification.method !== OUTCOME_METHOD) return null;
  const params = asRecord(notification.params);
  const outcome = typeof params.outcome === "string" ? params.outcome : "";
  const sessionId = typeof params.sessionId === "string" ? params.sessionId : "";
  const kind = OUTCOME_NOTICES[outcome] ?? { severity: "info", title: "Событие прогона" };
  const description = textOf(params.payload) ?? textOf(params.reason);
  const notice: ProviderNotice = {
    id: `yeah-${outcome}-${sessionId}`,
    severity: kind.severity,
    title: kind.title,
  };
  // Описание есть только когда есть о чем сказать: пустое поле оркестратор
  // показал бы как пустое уведомление, а не как уведомление без описания.
  if (description !== undefined) notice.description = description;
  return { type: "notice", notice };
}

