/**
 * Словарь Yeah на проводе ACP.
 *
 * ACP не знает двух вещей, которые ядро Yeah умеет: исход прогона и расход
 * хода.  Обе едут методами самого Yeah, и едут они только тем, кто попросил
 * их в `_meta` возможностей клиента.  Клиент, который ничего не объявил,
 * получает чистый ACP.
 *
 * Словарь лежит здесь, а не в модуле запуска: его читает и процессный путь
 * плагина, и сервисный, а сервисный путь должен работать без библиотек
 * процесса.
 */

/**
 * Форма сообщения ACP, с которой работает словарь.
 *
 * Тип объявлен здесь, а не взят у библиотеки процесса: словарь лежит в общем
 * бандле плагина, а общий бандл плагина не смеет импортировать серверные
 * модули — сборка плагина такой импорт отвергает. Поэтому общий бандл
 * описывает провод сам, а серверные модули пользуются этим описанием: формы
 * сообщений у них те же.
 */
export type YeahStreamMessage =
  | {
      jsonrpc: "2.0";
      id: string | number | null;
      method: string;
      params?: unknown;
    }
  | {
      jsonrpc: "2.0";
      method: string;
      params?: unknown;
    }
  | {
      jsonrpc: "2.0";
      id: string | number | null;
      result: unknown;
    }
  | {
      jsonrpc: "2.0";
      id: string | number | null;
      error: {
        code: number;
        message: string;
        data?: unknown;
      };
    };

/** Метод уведомления ядра об исходе прогона. */
export const OUTCOME_METHOD = "yeah/outcome";

/**
 * Ключ объявления в `_meta` возможностей клиента.
 *
 * Ядро шлёт исход прогона тем, кто его попросил, и никому больше: ключ в
 * `_meta` возможностей клиента — это просьба.
 */
export const RUN_OUTCOME_KEY = "yeah.runOutcome";

/** Метод уведомления ядра о расходе хода. */
export const USAGE_METHOD = "yeah/usage";

/** Ключ объявления в `_meta` возможностей клиента: расход хода. */
export const USAGE_KEY = "yeah.usage";

/**
 * Значение объекта: любой не-объект — пустой объект.
 *
 * Провод присылает то, что прислал, и разбирать это — работа плагина: ядро
 * не знает, как выглядит сообщение оркестратора, а оркестратор не знает,
 * как выглядит словарь ядра.
 */
export function asRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

/**
 * Запрос `initialize` с объявленным словарём Yeah.
 *
 * Запрос пишет демон оркестратора, и в нём нет ничего о словаре Yeah:
 * плагин перехватывает запрос на пути к ядру и кладёт в `_meta` возможностей
 * клиента просьбы -- об исходе прогона и о расходе хода.  Больше просить
 * нечем.
 *
 * Запрос меняется в одном месте: всё, что прислал оркестратор, остаётся на
 * месте, а отсутствующие `clientCapabilities` создаются — без них ядро не
 * увидит объявления, и запрос не должен из-за этого падать.
 */
export function yeahInitializeRequest(message: YeahStreamMessage): YeahStreamMessage {
  if (!("id" in message) || !("method" in message)) return message;
  if (message.method !== "initialize") return message;
  const params = asRecord(message.params);
  const capabilities = asRecord(params.clientCapabilities);
  const meta = asRecord(capabilities._meta);
  return {
    ...message,
    params: {
      ...params,
      clientCapabilities: {
        ...capabilities,
        _meta: { ...meta, [RUN_OUTCOME_KEY]: true, [USAGE_KEY]: true },
      },
    },
  };
}
