/**
 * Путь к корню ядра Yeah.
 *
 * Плагин живёт в репозитории ядра (`plugin/yeah-provider`), но собранный
 * бандл не знает, где он лежит: демон Paseo выполняет бандл через `eval`, и
 * `__dirname` в нём не определён. Поэтому путь приходит извне — из переменной
 * окружения `YEAH_REPO_PATH`, — а если её нет, из настройки `repoPath`.
 */

/** Имя переменной окружения с корнем checkout'а ядра. */
export const ENV_REPO = "YEAH_REPO_PATH";

/** Корень checkout'а ядра на этой машине. */
export const DEFAULT_REPO_PATH = "/home/az/Projects/yeah";

/**
 * Корень ядра из окружения, иначе FALLBACK.
 *
 * Пустое значение окружения — это отсутствие значения: путь ядра не может
 * быть пустым, и пустой `load-path` ломает ядро.
 */
export function repoPathFromEnv(fallback: string = DEFAULT_REPO_PATH): string {
  const fromEnv = process.env[ENV_REPO];
  return fromEnv && fromEnv.trim() ? fromEnv.trim() : fallback;
}
