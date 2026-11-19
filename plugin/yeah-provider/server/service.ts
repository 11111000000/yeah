/**
 * Сервис Yeah: один Emacs на всех агентов оркестратора.
 *
 * По умолчанию плагин поднимает свой Emacs на каждое соединение: агент
 * пришёл — Emacs стартовал, агент ушёл — Emacs ушёл.  Это просто, но Emacs на
 * соединение стоит дорого: бэкенд модели настраивается каждый раз, а на stdio
 * запрос, пришедший посреди хода, читается только после того, как ход
 * устаканился (`lib/yeah-acp.el`).
 *
 * Сервис — это тот же Emacs, но живой: он слушает сокет, и к нему подключаются
 * сессии.  Путь сокета, имя каталога и имя файла — те же, что у ядра
 * (`lib/yeah-service.el`), поэтому сервис поднимается и из Emacs, и из
 * плагина, и одно другого не выдаёт.
 *
 * Жизнь сервиса привязана к жизни хозяина: сервис смотрит на сокет жизни и
 * заканчивается, когда хозяин исчезает.  Сервис, переживший своего хозяина,
 * держит сокет и ждёт клиента, который не придёт.
 */
import { spawn, type ChildProcess } from "node:child_process";
import { existsSync, mkdirSync, rmSync } from "node:fs";
import net from "node:net";
import path from "node:path";
import type { AcpStream, AcpStreamMessage } from "@getpaseo/plugin/server/acp";
import { yeahInitializeRequest } from "../shared/vocabulary";
import { ndJsonChannel } from "./ndjson";

/** Имя переменной окружения, в которой сервис берёт путь своего сокета. */
export const ENV_SOCKET = "YEAH_ACP_SOCKET";

/** Имя переменной окружения, в которой сервис берёт сокет жизни хозяина. */
export const ENV_LIFE = "YEAH_LIFE_SOCKET";

/**
 * Каталог сокетов: тот же, что у ядра (`yeah-life-directory`).
 *
 * Сокет — это право управлять агентом с правами человека, поэтому каталог не
 * лежит в общедоступном месте: `XDG_RUNTIME_DIR`, а когда его нет — каталог
 * этого пользователя в `TMPDIR`.
 */
export function serviceDirectory(env: NodeJS.ProcessEnv = process.env): string {
  const runtime = env.XDG_RUNTIME_DIR;
  if (runtime && runtime.length > 0) return path.join(runtime, "yeah");
  const uid = typeof process.getuid === "function" ? process.getuid() : 0;
  return path.join(env.TMPDIR ?? "/tmp", `yeah-${uid}`);
}

/** Путь сокета сервиса NAME — то же имя, что у ядра. */
export function serviceSocketPath(name: string, env: NodeJS.ProcessEnv = process.env): string {
  return path.join(serviceDirectory(env), `yeah-service-${name}.sock`);
}

/**
 * Имя сокета жизни несёт pid хозяина, как в ядре: два хозяина не делят сокет.
 *
 * Ядро зовёт свой сокет жизни по своему тегу (`yeah-life-<тег>-<pid>.sock`),
 * и плагин зовёт его так же: имя каталога и имя файла те же, поэтому сервис,
 * поднятый из Emacs, и сервис, поднятый из плагина, не выдают друг друга.
 */
export function serviceLifeSocketPath(
  name: string,
  env: NodeJS.ProcessEnv = process.env,
): string {
  const tag = name.replace(/[^A-Za-z0-9]+/g, "-");
  return path.join(serviceDirectory(env), `yeah-life-${tag}-${process.pid}.sock`);
}

/** Живой сервис: сокет, по которому с ним говорит плагин. */
export interface YeahService {
  /** Путь сокета сервиса. */
  socketPath: string;
  /** Путь сокета жизни хозяина. */
  lifePath: string;
  /** Процесс сервиса; nil, когда сервис был уже запущен и нашёлся сам. */
  process: ChildProcess | null;
  /** Закрыть сервис, который поднял этот вызов. */
  close(): Promise<void>;
}

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

/**
 * Сокеты жизни, которые этот процесс уже слушает.
 *
 * Имя сокета несёт pid хозяина, поэтому у одного процесса он один.  Слушать
 * его дважды нельзя: второй слушатель получит «адрес занят» и не поднимет
 * сервис вовсе.
 */
const lifeServers = new Map<string, net.Server>();

/** Соединения сокетов жизни: их порвать нужно при уходе хозяина. */
const lifeConnections = new Map<string, Set<net.Socket>>();

/** Сокет жизни: слушатель и его соединения. */
interface LifeSocket {
  /** Слушатель сокета. */
  server: net.Server;
  /** Соединения, которые к сокету подключились: их надо порвать при уходе. */
  connections: Set<net.Socket>;
  /** Сокет поднял этот вызов, а не нашёлся готовым. */
  owned: boolean;
}

/**
 * Сокет жизни: по нему сервис видит, что хозяин ещё жив.
 *
 * Сокет слушает Node: ядро к нему подключается и следит за соединением.  Когда
 * хозяин уходит, ядро читает конец соединения и заканчивает сервис — так же,
 * как ребёнок, который знает смерть родителя по закрытой трубе.
 */
async function openLifeSocket(lifePath: string): Promise<LifeSocket> {
  const existing = lifeServers.get(lifePath);
  if (existing) {
    return { server: existing, connections: lifeConnections.get(lifePath) ?? new Set(), owned: false };
  }
  mkdirSync(path.dirname(lifePath), { recursive: true, mode: 0o700 });
  rmSync(lifePath, { force: true });
  const connections = new Set<net.Socket>();
  const server = net.createServer((socket) => {
    connections.add(socket);
    socket.on("close", () => connections.delete(socket));
    socket.resume();
  });
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(lifePath, () => resolve());
  });
  lifeServers.set(lifePath, server);
  lifeConnections.set(lifePath, connections);
  return { server, connections, owned: true };
}

/**
 * Закрыть сокет жизни: порвать соединения и закрыть слушатель.
 *
 * Порвать соединения надо раньше, чем ждать закрытия слушателя: слушатель
 * ждёт конца соединений, а соединение ждёт конца слушателя — и хозяин ждёт
 * вечно.  Порвали соединение — сервис увидел, что хозяин ушёл, и ушёл сам.
 */
async function closeLifeSocket(life: LifeSocket): Promise<void> {
  for (const connection of life.connections) connection.destroy();
  await new Promise<void>((resolve) => life.server.close(() => resolve()));
}

/** Параметры подъёма сервиса. */
export interface YeahServiceOptions {
  /** Имя сервиса: имя его сокета. */
  name: string;
  /** Команда сервиса; путь сокета приходит в ней через окружение. */
  command: readonly [string, ...string[]];
  /** Окружение сервиса. */
  env: NodeJS.ProcessEnv;
  /** Сколько ждать сокета сервиса, миллисекунд. */
  timeoutMs?: number;
}

/**
 * Жив ли сервис, который слушает на SOCKET-PATH.
 *
 * Файл сокета — не доказательство, что сервис жив: после смерти процесса файл
 * остаётся на диске, и следующий агент пришёл бы к мёртвому сокету.  Живость
 * проверяется соединением: кто-то слушает — сервис жив.
 *
 * Соединение, которое проверка открывает, сразу рвётся: сервис видит клиента,
 * который не говорит, и закрывает его.  Это его дело, а не наше.
 */
export async function serviceListens(
  socketPath: string,
  timeoutMs = 1_000,
): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    const socket = net.connect(socketPath);
    let settled = false;
    const settle = (alive: boolean): void => {
      if (settled) return;
      settled = true;
      socket.destroy();
      resolve(alive);
    };
    socket.setTimeout(timeoutMs, () => settle(false));
    socket.once("connect", () => settle(true));
    socket.once("error", () => settle(false));
  });
}

/**
 * Поднять сервис и дождаться его сокета.
 *
 * Сервис, который уже слушает, не поднимается второй раз: его сокет на месте,
 * и второй Emacs рядом с ним — это тот самый Emacs на соединение, которого
 * волна хочет больше не быть.
 */
export async function ensureService(options: YeahServiceOptions): Promise<YeahService> {
  const env = options.env;
  const socketPath = serviceSocketPath(options.name, env);
  const lifePath = serviceLifeSocketPath(options.name, env);
  const timeoutMs = options.timeoutMs ?? 30_000;

  if (existsSync(socketPath)) {
    // Сокет на месте — но это ещё не значит, что сервис жив: файл переживает
    // процесс, который умер.  Мёртвый сокет снимается, и сервис поднимается
    // заново: иначе следующий агент не придёт ни к какому ядру.
    if (await serviceListens(socketPath)) {
      return { socketPath, lifePath, process: null, close: async () => undefined };
    }
    rmSync(socketPath, { force: true });
  }

  const life = await openLifeSocket(lifePath);
  const childEnv: NodeJS.ProcessEnv = { ...env, [ENV_SOCKET]: socketPath, [ENV_LIFE]: lifePath };
  const [executable, ...args] = options.command;
  const child = spawn(executable, [...args], { env: childEnv, stdio: ["ignore", "pipe", "pipe"] });
  child.stderr?.on("data", (chunk: Buffer) => {
    const text = String(chunk).trimEnd();
    if (text) console.log(`[yeah] сервис Yeah: ${text}`);
  });
  child.on("exit", (code, signal) => {
    console.log(`[yeah] сервис Yeah завершился: код ${code}, сигнал ${signal}`);
  });

  const deadline = Date.now() + timeoutMs;
  while (!existsSync(socketPath) && Date.now() < deadline) {
    if (child.exitCode !== null) break;
    await sleep(50);
  }
  if (!existsSync(socketPath)) {
    child.kill("SIGTERM");
    await closeLifeSocket(life);
    if (life.owned) {
      lifeServers.delete(lifePath);
      lifeConnections.delete(lifePath);
    }
    rmSync(lifePath, { force: true });
    throw new Error(`[yeah] сервис Yeah не поднялся: сокет ${socketPath} не появился`);
  }

  return {
    socketPath,
    lifePath,
    process: child,
    close: async () => {
      // Сокет жизни закрывается первым: сервис видит, что хозяин ушёл, и
      // заканчивается сам.  Процесс — только если он ещё жив.
      await closeLifeSocket(life);
      if (life.owned) {
        lifeServers.delete(lifePath);
        lifeConnections.delete(lifePath);
      }
      rmSync(lifePath, { force: true });
      if (child.exitCode === null) child.kill("SIGTERM");
    },
  };
}

/**
 * Поток провода ACP по сокету сервиса.
 *
 * Провод тот же, что на stdio: JSON-RPC по строкам.  Разница в том, что
 * соединение — процесс, а не труба: запрос, пришедший посреди хода, сервис
 * читает и обрабатывает, не дожидаясь конца хода.
 */
export function acpServiceStream(socketPath: string): AcpStream {
  const connection = net.connect(socketPath);
  const channel = ndJsonChannel(connection);
  const writer = channel.writable.getWriter();
  const reader = channel.readable.getReader();

  // Закрытие соединения — это закрытие сессии, а не убийство сервиса:
  // сервис живёт, пока жив хозяин, и следующий агент получит тот же Emacs.
  const endInput = (): void => {
    if (!connection.destroyed) connection.end();
  };

  return {
    writable: new WritableStream({
      async write(message) {
        // Запрос `initialize` идёт от демона оркестратора, и в нём нет
        // ничего о словаре Yeah: плагин дополняет его на пути к ядру.
        await writer.write(yeahInitializeRequest(message as AcpStreamMessage) as never);
      },
      async close() {
        await writer.close().catch(() => undefined);
        endInput();
      },
      async abort(reason) {
        await writer.abort(reason).catch(() => undefined);
        endInput();
      },
    }),
    readable: new ReadableStream({
      async pull(controller) {
        try {
          const next = await reader.read();
          if (next.done) {
            controller.close();
            endInput();
          } else {
            controller.enqueue(next.value as never);
          }
        } catch (error) {
          controller.error(error);
          endInput();
        }
      },
      cancel(reason) {
        void reader.cancel(reason).catch(() => undefined);
        endInput();
      },
    }),
  };
}
