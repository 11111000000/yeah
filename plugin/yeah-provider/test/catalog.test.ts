import assert from "node:assert/strict";
import { test } from "node:test";
import type { ProviderCatalog } from "@getpaseo/plugin/server/provider";
import { yeahCatalog, yeahConfigure } from "../server/catalog";

const empty: ProviderCatalog = { models: [], modes: [] };

test("каталог без моделей получает модель плагина", () => {
  const catalog = yeahCatalog(empty, "MiniMax-M3.1-Flash");
  assert.deepEqual(catalog.models, [{ id: "MiniMax-M3.1-Flash", label: "MiniMax-M3.1-Flash" }]);
  assert.equal(catalog.defaultModel, "MiniMax-M3.1-Flash");
});

test("модель, которая уже есть в каталоге, не дублируется", () => {
  const catalog = yeahCatalog(
    { models: [{ id: "MiniMax-M3.1-Flash", label: "MiniMax-M3.1-Flash" }], modes: [] },
    "MiniMax-M3.1-Flash",
  );
  assert.equal(catalog.models.length, 1);
});

test("каталог без модели не меняется", () => {
  assert.deepEqual(yeahCatalog(empty, ""), empty);
});

test("запрос на ту же модель плагин принимает сам", async () => {
  assert.equal(await yeahConfigure({ target: "model", value: "MiniMax-M3.1-Flash" }, "MiniMax-M3.1-Flash"), "handled");
});

test("запрос на чужую модель уходит дальше и падает честно", async () => {
  assert.equal(await yeahConfigure({ target: "model", value: "другая" }, "MiniMax-M3.1-Flash"), "pass");
});

test("смена режима — не дело плагина", async () => {
  assert.equal(await yeahConfigure({ target: "mode", value: "build" }, "MiniMax-M3.1-Flash"), "pass");
});
