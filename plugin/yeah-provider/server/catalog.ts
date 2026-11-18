/**
 * Каталог провайдера Yeah и смена модели по проводу.
 *
 * Ядро Yeah не публикует модели в ответе `session/new` и не знает
 * `session/set_model`: у него одна модель на процесс, и она приходит
 * окружением при старте. Поэтому плагин говорит о модели прямо: в каталог
 * провайдера попадает модель из настроек, а запрос на смену модели
 * плагин принимает сам — и только когда речь о той же модели.
 *
 * Модель, которой нет, плагин не выдаёт: такой запрос уходит дальше и
 * падает честно, без правды наполовину.
 */
import type { AcpConfigChange } from "@getpaseo/plugin/server/acp";
import type { ProviderCatalog } from "@getpaseo/plugin/server/provider";

/**
 * Дополнить каталог моделями, которых в нём нет.
 *
 * Каталог ядра пуст, а пустой каталог означает для Paseo «у провайдера нет
 * моделей»: агента с таким провайдером не создать. Модель ядра одна, и
 * она известна плагину точно.
 */
export function yeahCatalog(catalog: ProviderCatalog, model: string): ProviderCatalog {
  if (!model) return catalog;
  if (catalog.models.some((entry) => entry.id === model)) return catalog;
  return {
    ...catalog,
    models: [...catalog.models, { id: model, label: model }],
    defaultModel: catalog.defaultModel ?? model,
  };
}

/**
 * Обработать смену модели по проводу.
 *
 * Менять модель на лету нечем: процесс ACP стартовал с одной моделью, и
 * ядро не знает метода смены. Запрос на ту же модель — это уже то, что
 * работает, и плагин отвечает за него сам. Любой другой запрос плагин не
 * трогает: тогда ошибку видит человек.
 */
export async function yeahConfigure(
  change: AcpConfigChange,
  model: string,
): Promise<"handled" | "pass"> {
  if (change.target !== "model") return "pass";
  if (change.value === model) return "handled";
  return "pass";
}
