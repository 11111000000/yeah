import { defineSettings } from "@getpaseo/plugin";
import { z } from "zod";
import { repoPathFromEnv } from "./paths";

/**
 * Настройки провайдера Yeah.
 *
 * Ключ провайдера здесь не хранится: он лежит в файле окружения вне дерева
 * репозитория, и настраивается только путь к этому файлу. Настройки видны
 * человеку в настройках хоста Paseo.
 *
 * Плагин лежит в репозитории ядра (`plugin/yeah-provider`), но собранный
 * бандл не знает, где он лежит, поэтому корень ядра приходит из окружения
 * (`YEAH_REPO_PATH`) или из этой настройки.
 */
export const yeahSettings = defineSettings({
  id: "yeah",
  scope: "host",
  version: 1,
  schema: z.strictObject({
    /** Каталог ядра Yeah: там `lib/`, из которого грузятся модули. */
    repoPath: z.string().max(4096).default(repoPathFromEnv()),
    /** Каталог сборки gptel; пусто — искать в `~/.emacs.d/elpa`. */
    gptelPath: z.string().max(4096).default(""),
    /** Путь к Emacs; пусто — искать в известных местах. */
    emacsPath: z.string().max(4096).default(""),
    /** Имя модели провайдера: на ней сервер стартует. */
    model: z.string().max(200).default("MiniMax-M3.1-Flash"),
    /**
     * Модели провайдера: список через запятую.
     *
     * Модель сессии меняется по проводу, и gptel берёт только ту модель,
     * которую знает его бэкенд.  Пустой список — одна модель из `model`.
     */
    models: z.string().max(2000).default(""),
    /** Хост провайдера. */
    host: z.string().max(200).default("api.minimax.io"),
    /** Профиль разрешений: `build` спрашивает человека, `plan` запрещает, `auto` никого не спрашивает. */
    profile: z.union([z.literal("plan"), z.literal("build"), z.literal("auto")]).default("build"),
    /**
     * Размещение ядра: `spawn` — свой Emacs на соединение, `service` — один
     * Emacs на всех агентов, сессии приходят к нему по сокету.
     *
     * По умолчанию — `spawn`: так плагин работал, и человек ничего не
     * выбирал.  Сервисное размещение меняет то, как агент получает ядро, и
     * решение о нём — за человеком.
     */
    serviceMode: z.union([z.literal("spawn"), z.literal("service")]).default("spawn"),
    /** Имя сервиса: имя его сокета; сервисы с разным именем не мешают друг другу. */
    serviceName: z.string().max(200).default("paseo"),
    /** Файл окружения с ключом провайдера; вне дерева репозитория. */
    keyFile: z.string().max(4096).default("~/.config/yeah/live.env"),
    /** Каталог данных Yeah; пусто — умолчание ядра. */
    dataHome: z.string().max(4096).default(""),
  }),
});

/** Значения настроек провайдера. */
export type YeahSettingsValues = z.output<typeof yeahSettings.schema>;

/**
 * Модели провайдера: те, что перечислены в настройке, и модель запуска.
 *
 * Модель запуска есть в списке всегда: сервер стартует на ней, а gptel
 * берёт только ту модель, которую знает его бэкенд.  Пустой список — одна
 * модель запуска.
 */
export function yeahModelsOf(values: YeahSettingsValues): string[] {
  const listed = values.models
    .split(",")
    .map((name) => name.trim())
    .filter((name) => name.length > 0);
  const models = listed.length > 0 ? listed : [values.model];
  return models.includes(values.model) ? models : [values.model, ...models];
}
