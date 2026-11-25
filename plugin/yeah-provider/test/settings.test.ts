import assert from "node:assert/strict";
import { test } from "node:test";
import { yeahModelsOf, type YeahSettingsValues } from "../shared/settings";

const base: YeahSettingsValues = {
  repoPath: "/tmp/yeah",
  gptelPath: "",
  emacsPath: "",
  model: "MiniMax-M3.1-Flash",
  models: "",
  host: "api.minimax.io",
  endpoint: "/v1/chat/completions",
  profile: "build",
  serviceMode: "spawn",
  serviceName: "paseo",
  keyFile: "~/.config/yeah/live.env",
  dataHome: "",
};

test("пустой список моделей — одна модель запуска", () => {
  assert.deepEqual(yeahModelsOf(base), ["MiniMax-M3.1-Flash"]);
});

test("список моделей читается через запятую", () => {
  // Модель запуска есть в списке всегда, и она первая: на ней сервер
  // стартует, и она модель по умолчанию.
  assert.deepEqual(yeahModelsOf({ ...base, models: "model-a, model-b ,model-c" }), [
    "MiniMax-M3.1-Flash",
    "model-a",
    "model-b",
    "model-c",
  ]);
});

test("модель запуска есть в списке всегда", () => {
  assert.deepEqual(yeahModelsOf({ ...base, model: "model-a", models: "model-b" }), [
    "model-a",
    "model-b",
  ]);
});
