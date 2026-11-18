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
    /** Имя модели провайдера. */
    model: z.string().max(200).default("MiniMax-M3.1-Flash"),
    /** Хост провайдера. */
    host: z.string().max(200).default("api.minimax.io"),
    /** Профиль разрешений: `build` спрашивает человека, `plan` запрещает. */
    profile: z.union([z.literal("plan"), z.literal("build")]).default("build"),
    /** Файл окружения с ключом провайдера; вне дерева репозитория. */
    keyFile: z.string().max(4096).default("~/.config/yeah/live.env"),
    /** Каталог данных Yeah; пусто — умолчание ядра. */
    dataHome: z.string().max(4096).default(""),
  }),
});

/** Значения настроек провайдера. */
export type YeahSettingsValues = z.output<typeof yeahSettings.schema>;
