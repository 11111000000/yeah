import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { expandHome, readEnvFile, resolveEmacs } from "../server/environment";
import {
  ENV,
  LAUNCH_FORM,
  acpCommand,
  acpStream,
  launchEnv,
  yeahToolCallTransformer,
  type YeahLaunch,
} from "../server/yeah";
import { repoPathFromEnv } from "../shared/paths";

const here = __dirname;

const launch: YeahLaunch = {
  emacs: "/nix/store/whatever/bin/emacs",
  lib: path.join(repoPathFromEnv(), "lib"),
  gptel: "/home/az/.emacs.d/elpa/gptel-20261104.2111",
  model: "MiniMax-M3.1-Flash",
  host: "api.minimax.io",
  profile: "build",
  dataHome: "",
};

test("команда ACP — это Emacs в пакетном режиме и форма запуска", () => {
  const command = acpCommand(launch);
  assert.equal(command[0], launch.emacs);
  assert.equal(command[1], "-Q");
  assert.equal(command[2], "--batch");
  assert.equal(command[3], "--eval");
  assert.equal(command[4], LAUNCH_FORM);
});

test("форма запуска берёт живое из окружения, а не из текста команды", () => {
  for (const name of [ENV.lib, ENV.gptel, ENV.model, ENV.host, ENV.key, ENV.profile]) {
    assert.ok(LAUNCH_FORM.includes(name), `форма не читает ${name}`);
  }
  assert.ok(!LAUNCH_FORM.includes("MiniMax-M3.1-Flash\n"), "модель вшита в форму");
});

test("пустая переменная окружения — это отсутствие значения", () => {
  // Иначе пустой каталог попадает в `load-path`, а пустой каталог данных —
  // в `yeah-data-home`, и ядро ломается.
  assert.ok(LAUNCH_FORM.includes("string-empty-p"), "форма не различает пустое значение");
});

test("ключ провайдера не попадает в команду", () => {
  const secret = "sk-test-secret-value";
  const env = launchEnv(launch, secret, {});
  assert.equal(env[ENV.key], secret);
  assert.ok(!acpCommand(launch).join(" ").includes(secret));
  assert.ok(!LAUNCH_FORM.includes(secret));
});

test("окружение запуска несёт пути ядра и профиль", () => {
  const env = launchEnv({ ...launch, profile: "plan", dataHome: "/tmp/yeah-data" }, "k", {});
  assert.equal(env[ENV.profile], "plan");
  assert.equal(env[ENV.dataHome], "/tmp/yeah-data");
  assert.equal(env[ENV.lib], launch.lib);
  assert.equal(env[ENV.gptel], launch.gptel);
  assert.equal(env[ENV.model], launch.model);
  assert.equal(env[ENV.host], launch.host);
});

test("запуск не мутирует окружение плагина", () => {
  const before = process.env[ENV.key];
  launchEnv(launch, "sk-test-secret-value", {});
  assert.equal(process.env[ENV.key], before);
});

test("каталог Emacs попадает в PATH", () => {
  const env = launchEnv(launch, "k", { PATH: "/usr/bin" });
  assert.equal(env.PATH, `/nix/store/whatever/bin${path.delimiter}/usr/bin`);
});

test("файл окружения читается вместе с `export` и без кавычек", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "yeah-env-"));
  const file = path.join(directory, "live.env");
  writeFileSync(
    file,
    ["# комментарий", "export YEAH_TEST_KEY=abc123", "YEAH_TEST_HOST=api.minimax.io", 'export YEAH_TEST_MODEL="MiniMax-M3"'].join("\n"),
    "utf8",
  );
  const values = readEnvFile(file);
  assert.equal(values.YEAH_TEST_KEY, "abc123");
  assert.equal(values.YEAH_TEST_HOST, "api.minimax.io");
  assert.equal(values.YEAH_TEST_MODEL, "MiniMax-M3");
});

test("отсутствующий файл окружения — пустые значения, а не ошибка", () => {
  assert.deepEqual(readEnvFile("/nonexistent/yeah/live.env"), {});
});

test("соединитель поднимает процесс и говорит с ним по проводу", async () => {
  const stream = acpStream(
    [process.execPath, path.join(here, "fixtures", "fake-acp-agent.mjs")],
    { ...process.env, PROBE_MARKER: "доставлено" },
  );
  const writer = stream.writable.getWriter();
  const reader = stream.readable.getReader();
  await writer.write({
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: { protocolVersion: 1, clientCapabilities: {} },
  });
  const answer = await reader.read();
  assert.equal(answer.done, false);
  const message = answer.value as { result?: { marker?: string } };
  assert.equal(message.result?.marker, "доставлено");
  await writer.close();
});

test("трансформер ставит род вызова по имени инструмента", () => {
  const snapshot = yeahToolCallTransformer({
    id: "call-1",
    title: "edit",
    status: "pending",
    input: null,
    output: null,
    locations: [],
  });
  assert.equal(snapshot.kind, "edit");
});

test("род, который есть в проводе, не меняется", () => {
  const snapshot = yeahToolCallTransformer({
    id: "call-2",
    title: "edit",
    kind: "search",
    status: "pending",
    input: null,
    output: null,
    locations: [],
  });
  assert.equal(snapshot.kind, "search");
});

test("инструмент без известного рода остаётся без рода", () => {
  const snapshot = yeahToolCallTransformer({
    id: "call-3",
    title: "delegate-result",
    status: "pending",
    input: null,
    output: null,
    locations: [],
  });
  assert.equal(snapshot.kind, undefined);
});

test("имена аргументов правки переводятся в имена клиента", () => {
  const snapshot = yeahToolCallTransformer({
    id: "call-4",
    title: "edit",
    kind: "edit",
    status: "pending",
    input: {
      path: "answer.txt",
      old_str: "old",
      new_str: "new",
      version: "abc123",
    },
    output: null,
    locations: [],
  });
  assert.deepEqual(snapshot.input, {
    filePath: "answer.txt",
    oldString: "old",
    newString: "new",
    version: "abc123",
  });
});

test("вызов, который не правка, не меняется", () => {
  const snapshot = yeahToolCallTransformer({
    id: "call-5",
    title: "read",
    kind: "read",
    status: "pending",
    input: { path: "answer.txt" },
    output: null,
    locations: [],
  });
  assert.deepEqual(snapshot.input, { path: "answer.txt" });
});

test("Emacs ищется абсолютным путём", () => {
  const emacs = resolveEmacs();
  assert.ok(emacs.length > 0);
  assert.ok(path.isAbsolute(emacs) || emacs === "emacs");
});

test("`~` разворачивается в домашний каталог", () => {
  assert.ok(expandHome("~/.config/yeah/live.env").startsWith("/home/"));
});
