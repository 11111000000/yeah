/**
 * Каталог провайдера Yeah.
 *
 * Модель сессии меняется по проводу: ядро публикует модели в ответе
 * `session/new` и меняет модель сессии через `session/set_config_option`.
 * Поэтому плагин публикует каталог моделей, которые знает его бэкенд, и не
 * перехватывает смену модели: запрос уходит в ядро, и ядро решает, может ли
 * сессия работать на названной модели.
 *
 * Модель, которой нет, никто не выдаёт: запрос на такую модель падает в
 * ядре честно, без правды наполовину.
 */
import type { ProviderCatalog } from "@getpaseo/plugin/server/provider";

/**
 * Дополнить каталог моделями, которых в нём нет.
 *
 * Каталог ядра может быть пуст, а пустой каталог означает для Paseo «у
 * провайдера нет моделей»: агента с таким провайдером не создать. Модели
 * плагина известны точно — это те, которые зарегистрированы в бэкенде.
 */
export function yeahCatalog(
  catalog: ProviderCatalog,
  models: readonly string[],
): ProviderCatalog {
  let result = catalog;
  for (const model of models) {
    if (!model) continue;
    if (result.models.some((entry) => entry.id === model)) continue;
    result = {
      ...result,
      models: [...result.models, { id: model, label: model }],
    };
  }
  if (result.models.length > 0 && result.defaultModel === undefined) {
    result = { ...result, defaultModel: result.models[0]!.id };
  }
  return result;
}
