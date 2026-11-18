import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { DEFAULT_REPO_PATH, ENV_REPO, repoPathFromEnv } from "../shared/paths";

test("корень ядра по умолчанию — это checkout, где лежит `lib/yeah-acp.el`", () => {
  // Плагин лежит в репозитории ядра, и его путь по умолчанию должен указывать
  // на тот же checkout: иначе Emacs грузит `lib/` откуда-то ещё.
  assert.ok(
    existsSync(path.join(DEFAULT_REPO_PATH, "lib", "yeah-acp.el")),
    `в ${DEFAULT_REPO_PATH} нет lib/yeah-acp.el`,
  );
});

test("переменная окружения перекрывает путь по умолчанию", () => {
  const before = process.env[ENV_REPO];
  process.env[ENV_REPO] = "/tmp/other-checkout";
  try {
    assert.equal(repoPathFromEnv(), "/tmp/other-checkout");
  } finally {
    if (before === undefined) delete process.env[ENV_REPO];
    else process.env[ENV_REPO] = before;
  }
});

test("пустая переменная окружения — это отсутствие значения", () => {
  // Иначе пустой путь ядра попадёт в `load-path`, и ядро не грузится.
  const before = process.env[ENV_REPO];
  process.env[ENV_REPO] = "   ";
  try {
    assert.equal(repoPathFromEnv(), DEFAULT_REPO_PATH);
  } finally {
    if (before === undefined) delete process.env[ENV_REPO];
    else process.env[ENV_REPO] = before;
  }
});
