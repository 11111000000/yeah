import assert from "node:assert/strict";
import { test } from "node:test";
import type { ProviderCatalog } from "@getpaseo/plugin/server/provider";
import { yeahCatalog } from "../server/catalog";

const empty: ProviderCatalog = { models: [], modes: [] };

test("каталог без моделей получает модели плагина", () => {
  const catalog = yeahCatalog(empty, ["MiniMax-M3.1-Flash", "MiniMax-M2"]);
  assert.deepEqual(catalog.models, [
    { id: "MiniMax-M3.1-Flash", label: "MiniMax-M3.1-Flash" },
    { id: "MiniMax-M2", label: "MiniMax-M2" },
  ]);
  assert.equal(catalog.defaultModel, "MiniMax-M3.1-Flash");
});

test("модель, которая уже есть в каталоге, не дублируется", () => {
  const catalog = yeahCatalog(
    { models: [{ id: "MiniMax-M3.1-Flash", label: "MiniMax-M3.1-Flash" }], modes: [] },
    ["MiniMax-M3.1-Flash"],
  );
  assert.equal(catalog.models.length, 1);
});

test("каталог без моделей не меняется", () => {
  assert.deepEqual(yeahCatalog(empty, []), empty);
});

test("каталог с моделями ядра не теряет модель по умолчанию", () => {
  const catalog = yeahCatalog(
    { models: [{ id: "MiniMax-M2", label: "MiniMax-M2" }], modes: [], defaultModel: "MiniMax-M2" },
    ["MiniMax-M3.1-Flash"],
  );
  assert.equal(catalog.defaultModel, "MiniMax-M2");
  assert.equal(catalog.models.length, 2);
});
