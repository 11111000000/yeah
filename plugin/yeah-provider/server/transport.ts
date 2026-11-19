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
import { acpServiceStream, ensureService, type YeahService } from "./service";

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
  const service =
    options.service ??
    (await ensureService({
      name: serviceName,
      command: options.serviceCommand ?? serviceCommand(launch),
      env: launchEnv(launch, key),
    }));
  return { stream: acpServiceStream(service.socketPath), service };
}
