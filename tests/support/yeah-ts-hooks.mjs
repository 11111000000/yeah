/**
 * Крюк резолвера: относительный импорт без расширения — это файл `.ts`.
 *
 * Крюк не трогает ничего, кроме относительных импортов без расширения:
 * такой импорт в TypeScript значит файл рядом, и Node ищет `.ts`.
 */
export async function resolve(specifier, context, nextResolve) {
  if (/^\.{1,2}\//.test(specifier) && !/\.[cm]?[jt]sx?$/.test(specifier)) {
    try {
      return await nextResolve(`${specifier}.ts`, context);
    } catch {
      // Рядом нет файла `.ts` — импорт обычный, и Node разберётся сам.
    }
  }
  return nextResolve(specifier, context);
}
