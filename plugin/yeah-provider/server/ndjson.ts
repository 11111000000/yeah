/**
 * Провод JSON-RPC по строкам поверх сокета.
 *
 * Сервисный путь плагина говорит с ядром не через процесс, а через сокет, и
 * кадр задаёт сам: одно сообщение — одна строка, строка — UTF-8, строки
 * кончаются переводом строки.  Это то же правило, что и на stdio, и то же
 * правило, что понимает ядро (`lib/yeah-wire.el`).
 *
 * Свой код, а не библиотека процесса: у процесса кадр ставит SDK, у сокета
 * кадр ставит плагин, и плагин читает сокет и пишет в него сам.
 */
import type { Duplex } from "node:stream";

/** Канал провода: то, что пишется, и то, что читается. */
export interface NdJsonChannel {
  /** Пишет сообщение в канал; сообщение уходит одной строкой. */
  writable: WritableStream<unknown>;
  /** Читает сообщения канала; порядок сохраняется. */
  readable: ReadableStream<unknown>;
}

/**
 * Кадр поверх сокета.
 *
 * Чтение идёт из буфера: сокет отдаёт байты кусками, а сообщение может
 * прийти двумя кусками или несколькими сообщениями в одном куске.  Строка
 * собирается целиком и только потом разбирается, поэтому многобайтный
 * символ на границе кусков не портится.
 */
export function ndJsonChannel(socket: Duplex): NdJsonChannel {
  const pending: unknown[] = [];
  let wake: (() => void) | null = null;
  let closed = false;
  let buffer = Buffer.alloc(0);

  const notify = (): void => {
    const waker = wake;
    wake = null;
    if (waker) waker();
  };

  socket.on("data", (chunk: Buffer) => {
    buffer = Buffer.concat([buffer, chunk]);
    let index = buffer.indexOf(0x0a);
    while (index >= 0) {
      const line = buffer.subarray(0, index).toString("utf8").trim();
      buffer = buffer.subarray(index + 1);
      if (line.length > 0) {
        try {
          pending.push(JSON.parse(line));
        } catch {
          // Строка, которая не JSON, — не сообщение провода.  Ядро шлёт
          // только JSON, и молчание честнее, чем выдуманное сообщение.
          console.log("[yeah] сервис Yeah: на сокете пришла строка, которая не JSON");
        }
      }
      index = buffer.indexOf(0x0a);
    }
    if (pending.length > 0) notify();
  });

  const close = (): void => {
    closed = true;
    notify();
  };
  socket.on("end", close);
  socket.on("close", close);
  socket.on("error", close);

  const readable = new ReadableStream<unknown>({
    async pull(controller) {
      while (pending.length === 0 && !closed) {
        await new Promise<void>((resolve) => {
          wake = resolve;
        });
      }
      if (pending.length > 0) {
        controller.enqueue(pending.shift() as unknown);
        return;
      }
      controller.close();
    },
    cancel() {
      close();
      socket.end();
    },
  });

  const writable = new WritableStream<unknown>({
    async write(message) {
      const text = `${JSON.stringify(message)}\n`;
      const bytes = Buffer.from(text, "utf8");
      await new Promise<void>((resolve, reject) => {
        socket.write(bytes, (error) => (error ? reject(error) : resolve()));
      });
    },
    close() {
      socket.end();
    },
    abort() {
      socket.destroy();
    },
  });

  return { writable, readable };
}
