/**
 * Транспорт плагина: свой Emacs на соединение или общий сервис по сокету.
 *
 * Размещение выбирает человек: по умолчанию плагин ведёт себя как раньше —
 * поднимает Emacs на соединение.  В сервисном размещении Emacs один на всех
 * агентов оркестратора, и сессии приходят к нему по сокету.
 *
 * Выбор живёт здесь, а не в точке подключения, чтобы он был проверяем: путь
 * «спросить сервис или поднять свой» — это решение плагина, и проверка видит
 * его целиком, вместе с тем, что сервис переживает соединение.
 */
import type { AcpStream } from "@getpaseo/plugin/server/acp";
import { acpCommand, launchEnv, serviceCommand, type YeahLaunch } from "./launch";
import { acpServiceStream, ensureService, serviceListens, type YeahService } from "./service";

/** Размещение ядра: свой Emacs на соединение или общий сервис по сокету. */
export type YeahPlacement = "spawn" | "service";

/** Параметры выбора транспорта. */
export interface YeahTransportOptions {
  /** Запуск ядра: путь к Emacs, каталоги, модель, профиль прав. */
  launch: YeahLaunch;
  /** Ключ провайдера; значение не печатается и не сохраняется. */
  key: string;
  /** Размещение: `spawn` — свой Emacs на соединение, `service` — сервис. */
  mode: YeahPlacement;
  /** Имя сервиса: имя его сокета. */
  serviceName: string;
  /** Команда сервиса; пусто — команда из запуска. */
  serviceCommand?: readonly [string, ...string[]];
  /** Уже поднятый сервис: чтобы не поднять второй. */
  service?: YeahService | null;
}

/** Транспорт и сервис, который он поднял. */
export interface YeahTransport {
  /** Поток провода к ядру. */
  stream: AcpStream;
  /** Сервис, если транспорт сервисный. */
  service: YeahService | null;
}

/**
 * Поток провода к ядру — и сервис, если он понадобился.
 *
 * Сервисный путь поднимает сервис один раз: следующий агент приходит к тому же
 * Emacs, и его соединение не стоит ничего, кроме сокета.
 *
 * Ссылка на сервис — не доказательство, что сервис жив.  Ядро умирает (сигнал,
 * OOM-killer, падение), а ссылка в плагине остаётся: следующий агент приходит
 * к сокету, за которым нет ядра, и получает «ACP connection closed» вместо
 * работы.  Поэтому сервис из кэша проверяется тем же вопросом, который задаёт
 * волна 74: слушает ли сокет кто-нибудь.  Мёртвый сервис поднимается заново.
 */
export async function yeahTransport(options: YeahTransportOptions): Promise<YeahTransport> {
  const { launch, key, mode, serviceName } = options;
  if (mode !== "service") {
    // Библиотека процесса грузится здесь, а не при импорте модуля: сервисный
    // путь не должен зависеть от неё — сервисный путь работает там, где
    // процессный не нужен.
    const { acpStream } = await import("./yeah");
    return {
      stream: acpStream(acpCommand(launch), launchEnv(launch, key)),
      service: null,
    };
  }
  const cached = options.service;
  if (cached && (await serviceListens(cached.socketPath))) {
    return { stream: acpServiceStream(cached.socketPath), service: cached };
  }
  if (cached) {
    // Сервис из кэша мёртв: его сокет никто не слушает.  Старый убирается
    // (его сокет жизни закрывается), иначе следующий агент придёт к тому же
    // мёртвому сокету.
    console.log("[yeah] сервис Yeah мёртв: поднимаем новый");
    await cached.close().catch(() => undefined);
  }
  const service = await raiseService(options);
  return { stream: acpServiceStream(service.socketPath), service };
}

/**
 * Сервис, который поднимается прямо сейчас.
 *
 * Агенты приходят к плагину не по одному: пока сервис поднимается, приходит
 * второй, и второй не должен поднять второе ядро.  Обещание одно на всех, и
 * следующий агент ждёт его.
 */
let raising: Promise<YeahService> | null = null;

/** Поднять сервис — один раз, даже если агентов несколько. */
function raiseService(options: YeahTransportOptions): Promise<YeahService> {
  if (raising) return raising;
  const promise = ensureService({
    name: options.serviceName,
    command: options.serviceCommand ?? serviceCommand(options.launch),
    env: launchEnv(options.launch, options.key),
  });
  raising = promise;
  const forget = (): void => {
    if (raising === promise) raising = null;
  };
  promise.then(forget, forget);
  return promise;
}
