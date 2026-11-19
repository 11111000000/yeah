import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import net from "node:net";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import {
  ENV_LIFE,
  ENV_SOCKET,
  acpServiceStream,
  ensureService,
  serviceDirectory,
  serviceLifeSocketPath,
  serviceSocketPath,
} from "../server/service";
import { yeahTransport } from "../server/transport";
import type { YeahLaunch } from "../server/launch";

/**
 * Запуск для тестов: ядро тут не поднимается, проверяется путь до него.
 */
const launch: YeahLaunch = {
  emacs: "/bin/true",
  lib: "/tmp/yeah/lib",
  gptel: "",
  model: "MiniMax-M3.1-Flash",
  models: ["MiniMax-M3.1-Flash"],
  host: "api.minimax.io",
  profile: "build",
  dataHome: "",
};

/** Каталог сокетов теста: свой, чтобы проверка не мешала живому сервису. */
function sandbox(): { root: string; env: NodeJS.ProcessEnv } {
  const root = mkdtempSync(path.join(tmpdir(), "yeah-service-"));
  return { root, env: { ...process.env, XDG_RUNTIME_DIR: root } };
}

test("каталог сокетов — тот же, что у ядра", () => {
  const { root, env } = sandbox();
  try {
    assert.equal(serviceDirectory(env), path.join(root, "yeah"));
    // Без `XDG_RUNTIME_DIR` каталог пользователя в `TMPDIR`, а не общий `/tmp`.
    const bare = serviceDirectory({ TMPDIR: "/tmp" });
    assert.equal(bare, path.join("/tmp", `yeah-${process.getuid?.() ?? 0}`));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("имя сокета сервиса — то же, что у ядра", () => {
  const { root, env } = sandbox();
  try {
    assert.equal(
      serviceSocketPath("paseo", env),
      path.join(root, "yeah", "yeah-service-paseo.sock"),
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("сокет жизни несёт pid хозяина: два хозяина не делят сокет", () => {
  const { root, env } = sandbox();
  try {
    const life = serviceLifeSocketPath("paseo", env);
    assert.match(path.basename(life), /^yeah-life-paseo-\d+\.sock$/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("живой сервис не поднимается второй раз", async () => {
  const { root, env } = sandbox();
  try {
    const name = "reuse";
    const socketPath = serviceSocketPath(name, env);
    // Сервис живой: на сокете кто-то слушает, и второй Emacs рядом с ним не
    // нужен.  Файла сокета самого по себе мало — его переживает процесс,
    // который умер.
    mkdirSync(path.dirname(socketPath), { recursive: true });
    const listener = net.createServer(() => undefined);
    await new Promise<void>((resolve) => listener.listen(socketPath, resolve));
    try {
      const service = await ensureService({
        name,
        command: ["/bin/false"],
        env,
      });
      assert.equal(service.socketPath, socketPath);
      assert.equal(service.process, null, "сервис поднялся второй раз");
    } finally {
      await new Promise<void>((resolve) => listener.close(() => resolve()));
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("мёртвый сокет не выдаёт себя за живой сервис", async () => {
  const { root, env } = sandbox();
  try {
    const name = "dead";
    const socketPath = serviceSocketPath(name, env);
    // Файл сокета остался от процесса, который умер: никто его не слушает.
    mkdirSync(path.dirname(socketPath), { recursive: true });
    writeFileSync(socketPath, "");
    const report = path.join(root, "raised.txt");
    const command: [string, ...string[]] = [
      "/bin/sh",
      "-c",
      'mkdir -p "$(dirname "$1")" && : > "$1" && printf "%s\\n" "$YEAH_ACP_SOCKET" > "$2"',
      "sh",
      socketPath,
      report,
    ];
    const service = await ensureService({ name, command, env, timeoutMs: 10_000 });
    try {
      assert.ok(service.process, "плагин поверил мёртвому сокету и не поднял сервис");
      assert.equal(readFileSync(report, "utf8").trim(), socketPath);
    } finally {
      await service.close();
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("сервис получает путь сокета и сокет жизни через окружение", async () => {
  const { root, env } = sandbox();
  try {
    const name = "raised";
    const socketPath = serviceSocketPath(name, env);
    const report = path.join(root, "env.txt");
    // Команда создаёт сокет и пишет в файл то, что пришло в окружении:
    // сервис берёт путь сокета и путь жизни не из аргументов, а оттуда.
    const command: [string, ...string[]] = [
      "/bin/sh",
      "-c",
      'mkdir -p "$(dirname "$1")" && : > "$1" && printf "%s\\n%s" "$YEAH_ACP_SOCKET" "$YEAH_LIFE_SOCKET" > "$2"',
      "sh",
      socketPath,
      report,
    ];
    const service = await ensureService({ name, command, env, timeoutMs: 10_000 });
    try {
      assert.ok(service.process, "сервис не поднялся");
      const written = readFileSync(report, "utf8").split("\n");
      assert.equal(written[0], socketPath);
      assert.equal(written[1], service.lifePath);
    } finally {
      await service.close();
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("плагин говорит с сервисом по сокету", async () => {
  const { root, env } = sandbox();
  const socketPath = path.join(root, "yeah", "yeah-service-probe.sock");
  mkdirSync(path.dirname(socketPath), { recursive: true });
  const server = net.createServer((socket) => {
    let buffer = "";
    socket.on("data", (chunk: Buffer) => {
      buffer += chunk.toString("utf8");
      let index = buffer.indexOf("\n");
      while (index >= 0) {
        const line = buffer.slice(0, index);
        buffer = buffer.slice(index + 1);
        const message = JSON.parse(line) as { id?: number };
        socket.write(
          `${JSON.stringify({ jsonrpc: "2.0", id: message.id ?? null, result: { ok: true } })}\n`,
        );
        index = buffer.indexOf("\n");
      }
    });
  });
  await new Promise<void>((resolve) => server.listen(socketPath, () => resolve()));
  try {
    const stream = acpServiceStream(socketPath);
    const writer = stream.writable.getWriter();
    const reader = stream.readable.getReader();
    await writer.write({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: { protocolVersion: 1, clientCapabilities: {} },
    } as never);
    const answer = await reader.read();
    assert.equal(answer.done, false);
    const message = answer.value as { result?: { ok?: boolean } };
    assert.equal(message.result?.ok, true);
    await writer.close();
  } finally {
    await new Promise<void>((resolve) => server.close(() => resolve()));
    rmSync(root, { recursive: true, force: true });
  }
});

test("размещение выбирается в одном месте", async () => {
  const { root, env } = sandbox();
  try {
    // Поддельный Emacs: процессное размещение должно поднять процесс и не
    // должно поднимать сервис.
    const fake = path.join(root, "emacs");
    writeFileSync(fake, "#!/bin/sh\nexit 0\n");
    chmodSync(fake, 0o755);
    // Процессное размещение сервиса не поднимает: свой Emacs на соединение.
    const spawned = await yeahTransport({
      launch: { ...launch, emacs: fake },
      key: "k",
      mode: "spawn",
      serviceName: "paseo",
    });
    assert.equal(spawned.service, null);

    // Сервисное размещение приходит к живому сервису, а не поднимает свой.
    const socketPath = serviceSocketPath("paseo", env);
    mkdirSync(path.dirname(socketPath), { recursive: true });
    writeFileSync(socketPath, "");
    const served = await yeahTransport({
      launch,
      key: "k",
      mode: "service",
      serviceName: "paseo",
      service: {
        socketPath,
        lifePath: serviceLifeSocketPath("paseo", env),
        process: null,
        close: async () => undefined,
      },
    });
    assert.ok(served.service, "сервисное размещение не дало сервис");
    assert.equal(served.service?.socketPath, socketPath);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("имён переменных окружения не сменилось", () => {
  assert.equal(ENV_SOCKET, "YEAH_ACP_SOCKET");
  assert.equal(ENV_LIFE, "YEAH_LIFE_SOCKET");
});
