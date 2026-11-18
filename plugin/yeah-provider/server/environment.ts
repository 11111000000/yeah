/**
 * Разрешение путей и чтение файла окружения.
 *
 * Всё, что нужно запустить ACP-сервер Yeah, ищется на машине хоста: Emacs,
 * сборка gptel и файл с ключом провайдера. Ключ никогда не попадает в
 * настройки плагина и никогда не печатается в журнал.
 */
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";

/** Развернуть `~` в начале пути. */
export function expandHome(value: string): string {
  return value.startsWith("~") ? path.join(homedir(), value.slice(1)) : value;
}

/** Известные места Emacs: PATH демона не содержит профиля Nix. */
const EMACS_CANDIDATES = [
  "~/.nix-profile/bin/emacs",
  "/run/current-system/sw/bin/emacs",
  "/usr/bin/emacs",
  "/usr/local/bin/emacs",
];

/**
 * Найти Emacs: явный путь, переменная окружения, известные места, `which`.
 * Путь абсолютный — процесс ACP запускается без PATH профиля Nix.
 */
export function resolveEmacs(explicit = ""): string {
  const candidates = [explicit, process.env.EMACS ?? "", ...EMACS_CANDIDATES];
  for (const candidate of candidates) {
    if (!candidate) continue;
    const expanded = expandHome(candidate);
    if (existsSync(expanded)) return expanded;
  }
  try {
    const found = execFileSync("which", ["emacs"], { encoding: "utf8" }).trim();
    if (found) return found;
  } catch {
    // `which` может отсутствовать: имя команды остаётся верным для хоста.
  }
  return "emacs";
}

/**
 * Найти каталог gptel: явный путь, затем свежайшая сборка в `elpa`.
 * Пустой результат означает, что на хосте нет gptel, и об этом сообщает
 * сам ACP-сервер, а не плагин.
 */
export function resolveGptelDir(explicit = ""): string {
  if (explicit) return expandHome(explicit);
  const elpa = path.join(homedir(), ".emacs.d", "elpa");
  try {
    const builds = readdirSync(elpa)
      .filter((name) => name.startsWith("gptel-"))
      .sort();
    const last = builds[builds.length - 1];
    if (last) return path.join(elpa, last);
  } catch {
    // Каталога `elpa` нет: ACP-сервер скажет об этом сам.
  }
  return "";
}

/**
 * Прочитать `KEY=value` из файла окружения.
 *
 * Строка `export KEY=value` — обычный способ записи таких файлов, и
 * префикс `export` пропускается. Значения в кавычках очищаются.
 */
export function readEnvFile(file: string): Record<string, string> {
  const values: Record<string, string> = {};
  let text: string;
  try {
    text = readFileSync(file, "utf8");
  } catch {
    return values;
  }
  for (const line of text.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const body = trimmed.startsWith("export ") ? trimmed.slice(7).trim() : trimmed;
    const equals = body.indexOf("=");
    if (equals <= 0) continue;
    const name = body.slice(0, equals).trim();
    const value = body
      .slice(equals + 1)
      .trim()
      .replace(/^["']/, "")
      .replace(/["']$/, "");
    if (name) values[name] = value;
  }
  return values;
}
