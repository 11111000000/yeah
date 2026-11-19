# Yeah на Android: разбор ошибки установки и способы поставить

**Дата анализа:** 2026-11-18 (первая волна), 2026-11-19 (вторая волна — сетевое
исследование).
**Что это:** анализ и рекомендации. Код, конфигурация и документация репозитория не
менялись; этот файл — единственное добавление, и он **не** зарегистрирован в
`spec.json`/`waves/` (вне math-coding, по AGENTS.md это отдельная работа волны).

**Структура:** часть I (§1–§9) — разбор ошибки и варианты установки по состоянию
репозитория; часть II (§10–§14) — сетевое исследование от 2026-11-19: механизм
интеграции Emacs с Termux, как люди реально пользуются Emacs на Android, зачем он
нужен, а также уточнения к первой волне. Части не перенумеровывались; §13
фиксирует, где вторая волна исправляет первую.

**Окружение, из которого пришла ошибка:** приложение Emacs на Android, package id
`org.gnu.emacs`, домашний каталог `/data/data/org.gnu.emacs/files/.emacs.d`.

---

## 1. Что именно означает ошибка

Стек из сообщения:

```
package-vc-install → package-vc--unpack → vc-clone → vc-git-clone
  → vc-git--call → process-file "git" → file-missing "Searching for program" "git"
```

`file-missing` с текстом «Searching for program» — это ошибка `executable-find`:
**программы `git` нет в PATH процесса Emacs**. Ничего больше не сломано: `package-vc`
дошёл до клонирования и остановился ровно на поиске бинарника.

Инструкция в `README.md:329-335` —

```elisp
(package-vc-install
 '(yeah :url "https://github.com/11111000000/yeah.git" :lisp-dir "lib"))
```

— предполагает машину, на которой `git` уже есть. На Android приложение Emacs её не
содержит, поэтому инструкция «как есть» здесь не работает. Это не баг Yeah и не
баг package.el: это несовпадение среды.

---

## 2. Почему «просто доставить git» внутрь приложения не получится

- Приложение Emacs — обычное Android-приложение: свой UID, свой приватный каталог
  `/data/data/org.gnu.emacs/files`, в PATH только `/system/bin` (toybox: `sh`, `env`,
  `cat`, `ls`, …). `git`, `tar`, `curl` туда не входят и появляться не откуда.
- `git` на Android живёт в Termux: `/data/data/com.termux/files/usr/bin/git`. Это
  **другое приложение, другой UID**, каталог Termux закрыт правами `0700`, а SELinux
  запрещает доступ к данным чужого приложения. Даже если дописать этот путь в PATH
  внутри Emacs, запуск бинарника будет отклонён ядром/SELinux — прав на то, чтобы
  открыть каталог Termux, у Emacs нет.
- Обходной путь `termux-exec` (Termux:API) тоже закрыт: по README самого
  termux-api приложение должно быть подписано **тем же ключом**, что и Termux, и
  «only the main Termux app are allowed to call the API methods in this app».
  Emacs из F-Droid/Play подписан иначе → `termux-exec` из него не работает.

**Вывод:** внутри приложения Emacs `git` не появится. Значит выбирать надо между
«поставить harness туда, где есть POSIX-окружение» (Termux) и «поставить harness
в приложение, но без git и без package.el» (ручная раскладка файлов).

---

## 3. Что сломается дальше, если починить только `git`

Ошибка `git` — первая в цепочке. Дальше появятся следующие (все проверены по коду):

| Что | Где в коде | Что это значит на Android |
|---|---|---|
| bootstrap ставит gptel и Yeah через `package-vc` | `install/yeah-bootstrap.el:33-39` | Скрипт тоже требует `git`; MELPA-путь (`package-install`) требует распаковки tar — `tar` в приложении нет |
| Yeah принимает только gptel **0.9.9.5 / 0.9.9.6** | `lib/yeah-gptel.el:40-41` | «Свежая» версия из MELPA не подойдёт; bootstrap намеренно пиннит ревизию `v0.9.9.6` (`install/yeah-bootstrap.el:28`) |
| gptel 0.9.9.6 — не один файл | дерево тега: 19 `.el` (`gptel.el`, `gptel-request.el`, `gptel-transient.el`, …) | `gptel.el` на этапе `eval-and-compile` требует `gptel-request` (`gptel.el:222`) — «скачать один gptel.el» недостаточно |
| gptel тянет `transient ≥ 0.7.8` и `compat ≥ 30.1.0.0` | `gptel.el:7` (Package-Requires) | Ещё два пакета; `transient` нужен только ради меню gptel |
| без `curl` gptel уходит во встроенный HTTP | `gptel-request.el:102` (`gptel-use-curl` = `(and (executable-find "curl") t)`), запрос идёт через `url-retrieve` (`gptel-request.el:969`) | Работать будет, но только если у приложения есть TLS и доверенные сертификаты — **проверяется на устройстве** |
| git-инструменты самого Yeah зовут `git` подпроцессом | `lib/yeah-git.el` | `git_status`, `git_diff`, `git_commit` без git не работают |
| bash-инструмент зовёт `sh -c` | `lib/yeah-process.el:221` | `/system/bin/sh` в Android есть, но набор утилит — toybox (нет gcc, python, coreutils) |
| MCP-клиент зовёт `env` | `lib/yeah-mcp-client.el:74` | `/system/bin/env` есть, это единственная внешняя зависимость MCP |
| сервисное размещение ищет бинарник `emacs` | `lib/yeah-service.el:35`, `lib/yeah-placement.el:225` | В приложении Emacs бинарник не лежит в PATH как обычная программа → сервисный режим там, скорее всего, не поднимается |
| минимум Emacs **30.2** | `lib/yeah-doctor-ui.el:34` | Приложение на F-Droid сейчас **31.1** → по версии годится |

---

## 4. Вариант A — Termux + Emacs (рекомендуется)

Termux и есть POSIX-среда на Android: он держит **Emacs 31.1**
(`packages/emacs/build.sh`: `TERMUX_PKG_VERSION="31.1"`, `--with-gnutls`,
`--without-x` — терминальный) и обычные пакеты `git`, `tar`, `curl`. Инструкция из
README работает там без единой правки.

**Шаги**

1. Поставить Termux (F-Droid/Play) и в нём:

   ```sh
   pkg update
   pkg install git
   # при TLS-ошибках позже: pkg install ca-certificates
   ```

2. Забрать репозиторий:

   ```sh
   git clone https://github.com/11111000000/yeah.git ~/yeah
   ```

3. Поставить harness (одна строка, скрипт сам возьмёт gptel `v0.9.9.6` и Yeah):

   ```sh
   emacs -Q --batch -l ~/yeah/install/yeah-bootstrap.el
   ```

   Либо интерактивно в Emacs: `M-x package-vc-install` →
   `'(yeah :url "https://github.com/11111000000/yeah.git" :lisp-dir "lib")`.

4. Настроить транспорт модели (обычным способом): `gptel-api-key`, `gptel-backend`,
   `gptel-model`; затем `M-x yeah-doctor` и `M-x yeah`.

**Плюсы:** работает всё — git-инструменты, bash, service placement, ACP-сервер,
package.el. **Минусы:** терминальный Emacs; это ровно то, чего требует модель
развёртывания Yeah («service Emacs» — отдельный процесс, `README.md:12-16`).

---

## 5. Вариант B — ручная установка в приложение Emacs на Android (без package.el)

Цель: редактор Emacs на Android, внутри которого живёт агент. Ставится без `git`,
без `package.el`, копированием файлов.

**Шаги**

1. Скачать и распаковать на телефоне (Termux как инструмент загрузки):

   ```sh
   curl -L https://github.com/11111000000/yeah/archive/refs/heads/main.tar.gz -o yeah.tar.gz
   tar xzf yeah.tar.gz            # -> yeah-main/lib/*.el   (62 файла)

   curl -L https://github.com/karthink/gptel/archive/refs/tags/v0.9.9.6.tar.gz -o gptel.tar.gz
   tar xzf gptel.tar.gz            # -> gptel-0.9.9.6/*.el  (19 файлов, нужны все)
   ```

   Плюс `compat.el` (если нужен) и `transient.el` (только ради меню gptel) — с MELPA
   или GitHub.

2. Положить файлы **в общую память**: домашний каталог приложения Emacs
   (`/data/data/org.gnu.emacs/files/.emacs.d`) из Termux недоступен — это приватные
   данные другого приложения. Например:

   ```sh
   mkdir -p /sdcard/emacs-lisp/yeah /sdcard/emacs-lisp/gptel
   cp yeah-main/lib/*.el          /sdcard/emacs-lisp/yeah/
   cp gptel-0.9.9.6/*.el          /sdcard/emacs-lisp/gptel/
   ```

   Приложению Emacs нужно выдать разрешение на внешнее хранилище (по описанию
   F-Droid, разрешения в Android выдаются вручную в настройках системы).

3. В `~/.emacs.d/init.el` **приложения**:

   ```elisp
   (add-to-list 'load-path "/sdcard/emacs-lisp/yeah")
   (add-to-list 'load-path "/sdcard/emacs-lisp/gptel")
   (require 'gptel)
   (require 'yeah)
   (setq gptel-api-key "…")
   (setq gptel-backend 'openai)      ;; или другой, доступный без curl
   (setq gptel-model "…")
   ```

4. `M-x yeah-doctor` → `M-x yeah`.

**Что при этом не работает (обязано быть сказано прямо):**

- git-инструменты (`git_status`, `git_diff`, `git_commit`) — нет `git`;
- service placement и мост `emacsclient` — нужен бинарник `emacs` в PATH;
- `package.el`/MELPA внутри приложения — нет `tar`;
- HTTP gptel идёт через `url-retrieve` (встроенный HTTP Emacs) — **требует TLS и
  доверенных сертификатов в сборке приложения**; это главный риск этого варианта.

**Проверка на месте (в приложении Emacs, `M-:`):**

```elisp
M-: (list (executable-find "git") (executable-find "sh")
          (executable-find "curl") (executable-find "tar"))
M-: (url-retrieve-synchronously "https://melpa.org/packages/contents")
M-x emacs-version
```

Первый список покажет, что доступно; второй — работает ли TLS (если вернётся
ошибка, вариант B без доверенных сертификатов не поедет).

---

## 6. Вариант C — harness в Termux, доступ к нему по ACP

Yeah умеет говорить ACP двумя транспортами: `yeah-acp-serve` (stdio) и
`yeah-acp-serve-socket` (Unix-сокет или IPv4) — `docs/PASEO-INTEGRATION.md:92-95`,
`211-216`.

```sh
emacs -Q --batch -L ~/yeah/lib -l yeah-acp \
  --eval "(progn (setq yeah-data-home \"~/yeah-data\") (yeah-acp-serve))"
```

Тогда телефон — сервер агента, а редактором остаётся приложение Emacs, а клиентом
может быть любой ACP-клиент (в том числе Paseo; состояние интеграции — в
`docs/PASEO-INTEGRATION-PLAN.md`). Здесь гит нужен только в Termux, и он там есть.

---

## 7. Сводка вариантов

| | A: Termux + Emacs | B: приложение Emacs, ручная раскладка | C: Termux + ACP |
|---|---|---|---|
| git-инструменты Yeah | да | нет | да |
| bash-инструмент | да (полный POSIX) | частично (toybox) | да |
| service placement / bridge | да | нет | да |
| MELPA / package.el | да | нет | да |
| риск | терминальный Emacs | TLS/сертификаты, внешнее хранилище | клиент на другой стороне |

**Рекомендация:** если цель — «запустить Yeah на телефоне», это вариант A (и, если
нужен доступ с другого устройства, вариант C поверх него). Вариант B — только если
редактором обязан быть именно Android-приложение Emacs, и с пониманием, что
git-инструменты и сервисный режим там не заработают.

**Уточнение второй волны (§10, §12.3):** вариант A в этой таблице означает Emacs,
запущенный *внутри* Termux. Если Emacs должен быть именно приложением Emacs для
Android (вариант B), то появляется вариант **A′** (§10.5) — своя сборка Emacs с
общим shared user ID `com.termux` и подписью `java/emacs.keystore`, при которой
приложение получает доступ к `/data/data/com.termux/files` и, следовательно, к
`git`, `bash`, `tar` и всему окружению Termux. Стоковая сборка из F-Droid этого не
имеет (§10.4). Цена A′ — своя сборка APK и переподпись Termux тем же ключом; оба
шага не проверены на устройстве (§14).

---

## 8. Что проверено, а что осталось непроверенным

**Проверено источниками:**

- стек ошибки из вашего сообщения и семантика `file-missing`/`executable-find`;
- код репозитория (файлы и строки указаны выше);
- Termux держит Emacs 31.1 с GnuTLS — `packages/emacs/build.sh`;
- ограничение `termux-exec` подписью — README termux-api;
- gptel `v0.9.9.6`: дерево тега (19 файлов), `Package-Requires` в `gptel.el:7`,
  `gptel-use-curl`/`url-retrieve` в `gptel-request.el:102,969`;
- приложение Emacs на F-Droid: версия 31.1, описание про выдачу разрешений.

Вторая волна добавила проверку по внешним источникам (подробно — §10–§12):
механизм общего user ID и общего ключа подписи, поведение стоковой сборки F-Droid,
документация Termux и Termux:API по манифестам, рецепты сборки и переподписи.

**Не проверено (нужно на устройстве):**

- версия Emacs и наличие доверенных сертификатов в вашей сборке приложения;
- доступ приложения к `/sdcard` на вашей версии Android (SAF);
- ведёт ли себя `package.el` без `tar` (ошибка назовёт отсутствующую программу);
- действительно ли `termux-exec` недоступен из Emacs на вашей паре подписей
  (ожидаю «недоступен»).

Полный список непроверенного после второй волны — §14 (8 пунктов); там же отдельно
перечислено то, что может изменить выводы §5 и §7 (поведение общего user ID в
собственной сборке, §10.5).

---

## 9. Открытые вопросы (решает владелец)

1. **Считать ли Android поддерживаемой платформой.** Сейчас README говорит только
   «On Emacs 30.2» (`README.md:329`), платформа не названа; в репозитории нет ни
   одного упоминания Android/Termux. Если Android — цель, это решение, которое
   меняет и документацию, и волны.
2. **Нужен ли отдельный bootstrap для Android** (вариант B: раскладка файлов без
   package.el). Тогда это волна math-coding: новое намерение, проверка и claim в
   `spec.json`, а не только этот отчёт.
3. **Нужен ли `git` вообще в сценарии Android.** Внутри приложения он недостижим, а
   без него выпадают git-инструменты. Либо это принимается как ограничение
   платформы, либо harness живёт в Termux (варианты A/C), где git есть.

---

# Часть II. Сетевое исследование (вторая волна, 2026-11-19)

**Метод.** Чтение первоисточников по прямым адресам: руководство GNU Emacs (приложение H
«Emacs and Android»), дерево `java/` репозитория `emacs-mirror/emacs`, манифесты и файлы
сборки приложений Termux и Termux:API, рецепт сборки F-Droid (`metadata/org.gnu.emacs.yml`),
репозитории сообщества. Поисковые системы не использовались: `web_search` в этой сессии
требует входа в аккаунт MiniMax, а страницы выдачи закрывают автоматические запросы
(DuckDuckGo — CAPTCHA, Mojeek — 403). Все цитаты ниже взяты из указанных файлов; где перевод
мой, это отмечено.

**Коротко.** Механизм, который делает Emacs и Termux «одним целым», найден в официальных
источниках и состоит из двух вещей: **общий «shared user ID»** и **один ключ подписи**.
Стоковая сборка Emacs из F-Droid не имеет ни того, ни другого — поэтому Termux для неё
недостижим, и это не гипотеза, а свойство её манифеста. Собрать своё — можно, и рецепт
опубликован.

---

## 10. Механизм: общий user ID + общий ключ подписи

### 10.1 Что говорит руководство GNU

Приложение H руководства Emacs, подраздел H.9 «Installing Extra Software on Android»
(перевод мой):

> «Termux provides a package manager based on the Debian project's dpkg system … These
> packages are customarily installed from within a purpose-built terminal emulator
> application, but access is also granted to Emacs when it is built with the same
> application signing key, and its "shared user ID" is set to the same package name, as
> that of the terminal emulator program. The file `java/INSTALL` within the Emacs
> distribution illustrates how to build Emacs in this fashion.»

То есть условия ровно два: (1) Emacs подписан **тем же ключом**, что и Termux; (2) у Emacs
выставлен «shared user ID», равный package name терминала.

`java/INSTALL` из дерева Emacs, раздел «BUILDING WITH A SHARED USER ID» (строки 224–247,
перевод мой):

> «Sometimes it may be desirable to build Emacs so that it is able to access executables
> and application data from another program. To achieve this, that other program must have
> a "shared user ID", and be signed with the same signing key used to sign Emacs (normally
> `emacs.keystore`.)»
>
> `./configure --with-shared-user-id=MY.SHARED.USER.ID`
>
> For instance, `./configure --with-shared-user-id=com.termux` will result in Termux
> (https://termux.dev)'s application data being accessible to Emacs, within its own
> application data directory located at `/data/data/com.termux/files`.»

и предупреждение из того же файла:

> «Don't do this if you already have Emacs installed with a different shared user ID, as the
> system does not allow programs to change their user IDs after being installed.»

Как shared user ID попадает в приложение: `java/AndroidManifest.xml.in` содержит
плейсхолдеры `@ANDROID_SHARED_USER_ID@` и `@ANDROID_SHARED_USER_NAME@` (строки 34–35) —
значение подставляет `configure`, а не правка манифеста руками. В том же файле:
`package="org.gnu.emacs"`, `android:requestLegacyExternalStorage="true"`.

Ключ подписи лежит в открытом дереве Emacs: `java/emacs.keystore` (присутствует в списке
каталога `java/` — 2776 байт). Пароль от него там же, в `java/Makefile.in:84-88`:

```
SIGN_EMACS = -keystore $(srcdir)/emacs.keystore -storepass emacs1 $(JARSIGNER_FLAGS)
SIGN_EMACS_V2 = sign --v2-signing-enabled --ks $(srcdir)/emacs.keystore -debuggable-apk-permitted --ks-pass pass:emacs1
```

Сборка APK подписывается этим ключом (`java/Makefile.in:481-488`); там же — как перевыпустить
сам ключ, если истёк:

```
# When emacs.keystore expires, regenerate it with:
#  keytool -genkey -v -keystore emacs.keystore -alias "Emacs keystore" \
#   -keyalg RSA -sigalg  SHA1withRSA -keysize 2048 -validity 100000
```

Это публичные значения из открытого дерева Emacs; секретом они не являются.

### 10.2 Что объявляет сам Termux

Манифест `termux-app` (`app/src/main/AndroidManifest.xml`, master):

- `android:sharedUserId="${TERMUX_PACKAGE_NAME}"` — Termux **уже** объявляет shared user ID;
- в сборке `manifestPlaceholders.TERMUX_PACKAGE_NAME = "com.termux"`
  (`app/build.gradle:54`), namespace `com.termux` — то есть и applicationId, и shared user ID
  совпадают с `com.termux`;
- permission `${TERMUX_PACKAGE_NAME}.permission.RUN_COMMAND` с `android:protectionLevel="dangerous"`
  — объявление принадлежит Termux, выдаётся пользователем в настройках;
- `RunCommandService` — `exported="true"`, permission RUN_COMMAND, action
  `${TERMUX_PACKAGE_NAME}.RUN_COMMAND`: это и есть механизм, стоящий за `termux-exec`;
- провайдеры `${TERMUX_PACKAGE_NAME}.documents` (`TermuxDocumentsProvider`) и
  `${TERMUX_PACKAGE_NAME}.files` (`TermuxOpenReceiver$ContentProvider`, permission RUN_COMMAND).

Терминал и Termux:API — один и тот же код с разными `namespace`, но общий плейсхолдер:

| приложение | namespace / applicationId | `TERMUX_PACKAGE_NAME` (= shared user ID) |
|---|---|---|
| Termux | `com.termux` | `com.termux` |
| Termux:API | `com.termux.api` | `com.termux` |

То есть Termux:API — **другое приложение** с тем же shared user ID. Именно поэтому
`termux-exec` вообще возможен: манифест `termux-api` объявляет permission
`${TERMUX_PACKAGE_NAME}.sharedfiles.READ_WRITE` с `android:protectionLevel="signature"` и
провайдер `ShareAPI$ContentProvider` (authority `${TERMUX_PACKAGE_NAME}.sharedfiles`,
`exported="true"`, `grantUriPermissions="true"`). Уровень `signature` означает: доступ получает
только приложение, подписанное **тем же** ключом.

### 10.3 Следствие: три ступени

| ступень | что делается | что даёт |
|---|---|---|
| 1 | собрать Emacs с `--with-shared-user-id=com.termux` и подписать `java/emacs.keystore` | Emacs получает доступ к каталогу данных Termux `/data/data/com.termux/files`, где лежит `usr/bin/git`; приложения делят UID |
| 2 | переподписать Termux ключом `emacs.keystore` | ключи совпадают → пара ставится рядом; иначе установка откажется (см. ниже) |
| 3 | Termux:API / Termux:Boot / Termux:Tasker — тем же ключом и тем же shared user ID | работают `termux-exec` и контент-провайдер `sharedfiles` |

Почему переподписывают именно Termux, а не наоборот: ключ Termux закрыт, а ключ Emacs
(`java/emacs.keystore`) лежит в открытом дереве Emacs. Общего ключа можно добиться только
со стороны открытого ключа.

Готовый рецепт второй ступени опубликован сообществом: `johanwiden/termux-for-android-emacs`
— «Termux APK signed for Android Emacs, works on Android 15». README (перевод мой): APK
Termux версии «0.119.0-beta.3 (1022)», скачан с F-Droid 2025-08-21, переподписан ключом
Emacs; команда подписи «derived from» `java/Makefile.in`:

```
apksigner sign --v2-signing-enabled --ks emacs.keystore -debuggable-apk-permitted --ks-pass pass:emacs1 com.termux_1022.apk
```

Автор пишет, что переподписанный APK работает на его устройствах с актуальной версией
Android: OnePlus Open и Samsung Tab S8+. Отдельно он замечает, что не даёт указаний
на установку самих инструментов подписи — «I do not have a pointer to a good (and up to
date) instruction for how to install the relevant Android development tools». То есть
рецепт подписи проверен автором, а процедура подготовки инструментов — нет.

### 10.4 Почему стоковая сборка F-Droid не подходит

Рецепт сборки F-Droid для версии 31.1 (`metadata/org.gnu.emacs.yml` в `fdroiddata`,
`versionName: '31.1'`, `ndk: r27d`, четыре ABI) — целиком:

```
./autogen.sh
./configure --with-android=$SDK/platforms/android-36/android.jar --without-android-debug
  --with-gif --with-gnutls --with-harfbuzz --with-jpeg --with-native-compilation=no
  --with-ndk-path="$(cat emacs_deps/search-path.txt)" --with-png --with-selinux --with-sqlite3
  --with-tiff --with-tree-sitter --with-webp --with-xml2
  ANDROID_CC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/i686-linux-android22-clang
  SDK_BUILD_TOOLS=$SDK/build-tools/36.1.0
make all
```

- Поиск по всему файлу метаданных `shared-user-id|sharedUserId|keystore` → **0 совпадений**:
  ни общего user ID, ни своего ключа подписи сборка не задаёт.
- Собранный F-Droid пакет подписывает **своим** ключом: сборка даёт неподписанный APK
  (`fdroidserver/build.py`: `output_dir = 'unsigned'`), а подпись делается при публикации
  ключом репозитория (`fdroidserver/publish.py`: `'-keystore', config['keystore']`).

Итог: у приложения Emacs из F-Droid нет ни общего user ID с Termux, ни общего ключа →
доступа к `/data/data/com.termux/files` у него нет. Это свойство его манифеста, а не
предположение.

### 10.5 Рецепт: своя сборка Emacs (вариант A′)

1. Нужны Android SDK и NDK на другой, не-Android, ОС. Для Android 15+ — NDK r27 или новее:
   «you are advised to build Emacs with the NDK r27 or better, if producing binaries to run on
   aarch64 or x86_64 devices and Android 15 or future releases» (`java/INSTALL`, раздел
   «16 KB PAGE SIZES»).
2. Собрать с общим user ID Termux:

   ```
   ./configure --with-android=$SDK/platforms/android-36/android.jar \
     --with-shared-user-id=com.termux \
     ANDROID_CC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android22-clang \
     SDK_BUILD_TOOLS=$SDK/build-tools/36.1.0
   make all
   ```

   (опции `--with-gnutls`, `--with-png` и прочие — как в рецепте F-Droid выше; они
   определяют набор возможностей сборки, а не связь с Termux).
3. `make all` даёт `java/emacs-*.apk`, подписанный `java/emacs.keystore` (пароль `emacs1`) —
   `java/Makefile.in:481-488`.
4. Termux из F-Droid переподписать ключом Emacs (рецепт §10.3). Стоковый Termux со своим
   ключом рядом не установится: у них один shared user ID, а подписи разные — ожидаемая
   ошибка установки `INSTALL_FAILED_SHARED_USER_INCOMPATIBLE`. Старый Termux перед этим
   нужно удалить; старую установку Emacs — тоже (смена user ID после установки запрещена,
   см. цитату из `java/INSTALL`).

Проверка на устройстве, в Emacs (`M-:`):

```elisp
(list (executable-find "git")
      (file-directory-p "/data/data/com.termux/files/usr/bin")
      (file-exists-p "/data/data/com.termux/files/usr/bin/git"))
```

и обратная проверка в Termux:

```sh
ls /data/data/org.gnu.emacs/files
```

Что здесь стоит сказать прямо:

- **Это расширение доверия, а не только удобство.** Общий user ID означает, что Emacs
  получает доступ ко всем данным Termux, включая `~/.termux/termux.properties` и всё, что
  пользователь туда положил.
- **Проверка на устройстве не проводилась** (см. §14): ни сборка, ни установка, ни
  фактический доступ к `git` из Emacs не подтверждены.
- Сборка NDK/Android SDK — операция на десятки минут и гигабайты; для «просто
  попробовать» она не обязательна: вариант A (Termux) работает без неё.

### 10.6 Что ещё даёт общий user ID (H.3)

- **app library**: «automatically appended to `exec-path` and made `exec-directory` upon
  startup, and contains utility executables alongside Emacs itself».
- Для скриптов, запущенных внутри приложений с тем же user ID, Emacs при старте делает
  симлинк каталога библиотеки на его традиционное место рядом с домашним каталогом:
  «For the convenience of scripts running within applications sharing the same user ID as
  Emacs (which have no access to the `exec-directory` variable), a fairly considerable effort
  is made at startup to symlink the application library directory to its traditional location
  within the parent of the app data directory».
- **app data** — домашний каталог Emacs, read-write; обычно симлинк на
  `/data/data/org.gnu.emacs/files`.
- **external storage** — `/sdcard`; на Android 11+ нужно разрешение «Files and Media» плюс
  `System -> Apps -> Special App Access -> All files access -> Emacs` («These settings are not
  present on some proprietary versions of Android»).
- **`/assets`** — read-only каталог с `etc`, `lisp`, `info`; эмуляция `ls` включена по
  умолчанию, потому что системный `ls` у разных производителей разный.

Практический вывод для нашей задачи: `git` из Termux лежит в
`/data/data/com.termux/files/usr/bin` — это не `/sdcard` и не каталог провайдера документов.
Значит, добраться до него можно **только** через общий user ID (или живя в Termux), и
«положить файлы на sdcard» здесь не помогает.

### 10.7 Уточнения к первой волне

Сводная таблица — в §13.

---

## 11. Как люди на самом деле пользуются Emacs на Android

### 11.1 Портированный Emacs внутри терминала (путь zielmicha)

`zielmicha/emacs-android` — README: «This is Emacs port for Android. This repo contains only
build scripts». Сборка:

```
cd native
git clone http://github.com/zielmicha/emacs.git emacs-src
./build.sh
```

Установка приложения:

```
git clone https://github.com/zielmicha/emacs-android-app.git
cd emacs-android-app
ant debug install
```

Само приложение — «Android Terminal Emulator», наследие `jackpal`:
«Emulates a reasonably large subset of Digital Equipment Corporation VT-100 terminal codes,
so that programs like "vi", "Emacs" and "NetHack" will display properly». Схема тут другая,
чем в §10: терминал на Android плюс Emacs, собранный как обычная консольная программа; общий
user ID здесь не нужен, `git` просто лежит в PATH терминала. По умолчанию приложение
скачивает готовую сборку Emacs с `emacs.zielm.com`; свой билд — `native/upload.sh
username@host:path` и правка `MIRROR=...` в `busyboxrc.sh`.

### 11.2 Разработка Android-приложений из Emacs

`mariusk/android-with-emacs` — «Notes and code for using Emacs for Android development».
Что там описано:

- `M-x compile` с gradle: функция `gradleMake` ищет `gradlew` вверх по дереву каталогов и
  ставит локальную переменную `compile-command` = `cd <dir>; ./gradlew assembleDebug`;
- распознавание ошибок компиляции: в `compilation-error-regexp-alist` добавляется
  `(":compile.*?\\(/.*?\\):\\([0-9]+\\): " 1 2)`, чтобы переход к строке ошибки по «следующей
  ошибке» работал;
- сборка + установка + запуск одной командой через локальные переменные в
  `MainActivity.java`:

  ```
  // Local Variables:
  // compile-command: "cd /home/marius/p/tournman/android/workspace/TournmanProject/; ./gradlew assembleDebug && adb install -r TournmanApplication/build/apk/TournmanApplication-debug-unaligned.apk && adb shell \"am start -n net.kjeldahl.tournman/.TournmanActivity\""
  // End:
  ```

- навигация по исходникам Android: `ggtags` поверх `global`, симлинк на
  `/opt/android-studio/sdk/sources/android-18/`, `gtags` в корне проекта даёт `GTAGS`,
  `GSYMS`, `GRTAGS`; `M-.` открывает ссылки, `M-*{` и `M-}` ходят по упоминаниям, что
  позволяет быстро выяснить, какой `import` нужен; `auto-complete` — дополнение.

Вывод: «Emacs на Android» на практике — это редактор на телефоне/планшете с одной кнопкой
«собрать, поставить на устройство, запустить». Это и есть ответ на вопрос «как люди
пользуются».

### 11.3 Конфиги

`jethrokuan/.emacs.d-android` (4★) — README целиком состоит из одной строки:
«Archived: Merged with main repository». То есть отдельного живого «Android-конфига» нет:
Android-специфичные куски слиты в основные dotfiles. В отчёте это надо называть именно так —
как слитое, а не как отдельную поддерживаемую раскладку.

### 11.4 Файлы, доступные приложению Emacs

| каталог | что это | права |
|---|---|---|
| `/assets` | `etc`, `lisp`, `info` из поставки | read-only; подпроцессы оттуда не стартуют |
| app data | домашний каталог Emacs (`~/.emacs.d`) | read-write |
| app library | бинарники приложения | автоматически в `exec-path`, `exec-directory` |
| `/sdcard` | внешнее хранилище | «Files and Media» (+ «All files access» на Android 11+) |
| `/content/storage/<authority>/<id>` | каталоги провайдеров документов | по запросу |

Про провайдеров документов (H.4): `M-x android-request-directory-access` открывает диалог
выбора каталога, содержимое появляется в `/content/storage/<authority>/<id>`, где
`authority` — имя провайдера, `id` — идентификатор каталога у провайдера;
`M-x android-relinquish-directory-access` — отпустить доступ. Ограничения: нельзя создавать
symlinks и hard links; провайдеры могут выполнять дорогие сетевые операции, поэтому доступ
может быть медленным; подпроцессы из этих каталогов не запускаются (cwd = домашний
каталог).

### 11.5 Механики приложения Emacs, полезные для агента

- **Обёртка `emacsclient`.** Emacs регистрирует её в системе как приложение, открывающее
  любой файл; при выборе запускает `emacsclient --reuse-frame --timeout=10 --no-wait <file>`
  и передаёт фокус открытому фрейму. Если Emacs не запущен — он стартует и получает файл
  как аргумент. Оговорка из руководства: «if that Emacs in turn does not start the Emacs
  server, subsequent attempts to open the file with the wrapper will fail» — сервер надо
  поднимать явно.
- **Обработчики `org://` и `mailto:`** регистрируются тем же способом; `mailto:` работает
  только при уже запущенном сервере Emacs.
- **Логи.** `adb logcat | grep -E "(android_run_debug_thread|[Ee]macs)"` с компьютера;
  внутри Emacs — асинхронная команда `logcat`.
- **Запуск Emacs вне сессии (H.5).** Бинарник `libandroid-emacs.so` установлен в каталог
  библиотеки приложения; чтобы запустить Emacs из оболочки, нужен `EMACS_CLASS_PATH` и
  готовый скрипт-обёртка:

  ```sh
  package_name=`pm path org.gnu.emacs 2>/dev/null </dev/null | sed 's/^package://'`
  emacs=
  EMACS_CLASS_PATH=$package_name
  ...
  exec $emacs "$@"
  ```

  `pm path` при этом «must be invoked in a particular way» — потоками в файл или pipe.
  Это ровно то, что нужно Yeah: модель развёртывания «service Emacs» (`README.md:12-16`)
  требует бинарника `emacs` в PATH, а на Android его нет — есть `libandroid-emacs.so` и
  обёртка.
- **Фоновые процессы.** На Android 12 могут убиваться процессы-потомки; рекомендация из
  руководства: `adb shell "settings put global settings_enable_monitor_phantom_procs false"`.

---

## 12. Зачем Emacs на Android, если «без всего остального»

### 12.1 Позиция проекта Emacs

Подраздел H.1 «Android History» (перевод мой): «Android is not designed to respect users'
freedom…» и «We support GNU Emacs on proprietary operating systems because we hope this taste
of freedom will inspire users to escape from them.» То есть поддержка Android сознательная,
но с прямой оговоркой: это «временное решение для несвободной системы».

### 12.2 Четыре практических ответа

1. **Редактор, которому не нужно ничего, кроме себя.** Приложение Emacs — самостоятельное:
   свой Lisp, свой `package.el`, свой редактор, работа офлайн, без аккаунта и без магазина.
   Busybox и Termux дают утилиты; Emacs даёт редактор и среду (Org, Magit, literate
   programming) — и не требует ничего «снаружи».
2. **Lisp как исполняемый конфиг.** То, чего не даёт ни один терминальный редактор:
   `.emacs.d/init.el` — это программа, а не файл настроек. Именно поэтому на Android
   Emacs пригоден как «сборочный станок»: сценарий из §11.2 (gradle → adb install → am start)
   описывается кодом, а не документацией.
3. **Фронт к POSIX-окружению.** Когда Emacs и Termux — одно приложение (общий user ID,
   §10) или Emacs работает в терминале (порт zielmicha, §11.1), редактор получает `git`,
   `grep`, `python`, `make` — и перестаёт быть просмотрщиком файлов.
4. **Точка входа для агентов.** Emacs — редактор с API: он умеет запускать команды,
   ходить по файлам, держать буферы и показывать результат. Для агента это удобная
   оболочка: рабочее окружение, журнал, обратная связь. Для Yeah это ровно тот класс
   инструмента, которым является сам Emacs (`README.md:12-16`).

### 12.3 Что это значит для Yeah

| вариант | Emacs | git / package.el | примечание |
|---|---|---|---|
| A | терминальный, в Termux | да | работает сразу, требует только Termux |
| B | приложение Emacs из F-Droid | нет | TLS и внешнее хранилище — главные риски |
| **A′** | приложение Emacs, **своя сборка** с `--with-shared-user-id=com.termux` | да | снимает ограничение B, но требует сборки APK и переподписи Termux |
| C | любой из вышеперечисленных | да (в Termux) | harness в Termux, доступ по ACP |

Практический порядок: сначала A (или C поверх A) — это работает сегодня и не требует ни
сборки, ни root. A′ имеет смысл, когда нужен именно GUI-редактор Emacs **и** git внутри
него.

### 12.4 Честная часть ответа

«Без всего остального» — это одновременно свобода и ограничения. Нет systemd и спуна,
Android выбивает фоновые процессы, доступ к файлам урезан scoped storage, экранная
клавиатура — не терминал, а сенсорный ввод. Emacs на Android — это Emacs с обрезанными
руками, а не «терминал в кармане». Сценарий из §11.2 показывает, что при этом остаётся
работающим.

---

## 13. Уточнения и противоречия между волнами

| Утверждение части I | Уточнение части II |
|---|---|
| «внутри приложения Emacs `git` не появится» (§2, вывод) | Верно **для стоковой сборки**: у F-Droid-сборки нет ни shared user ID, ни общего ключа (§10.4). Для собственной сборки с `--with-shared-user-id=com.termux` — появляется: каталог `/data/data/com.termux/files` доступен Emacs по прямому утверждению руководства (§10.1). Вывод §2 следует читать как «в приложении из F-Droid». |
| «`termux-exec` закрыт: приложение должно быть подписано тем же ключом» (§2) | Подтверждено и уточнено: в манифесте `termux-api` permission `sharedfiles.READ_WRITE` имеет `protectionLevel="signature"`, а оба приложения объявляют `android:sharedUserId="com.termux"`. Условие — совпадение **и** ключа, **и** shared user ID. |
| Вариант B — «без git» (§5, §7) | Остаётся верным для стоковой сборки; появляется вариант A′ (§10.5), который это ограничение снимает. |
| «service placement / bridge — нет» (§3, §7) | Для F-Droid-сборки по-прежнему нет бинарника `emacs` в PATH, но приложение само предоставляет обёртку `emacsclient` и бинарник `libandroid-emacs.so` (§11.5) — оценку стоит уточнить: серверный режим достижим, если поднимать его явно. |
| Версия приложения «31.1» (§8) | Согласуется: страница F-Droid показывает 31.1 (добавлена 27 августа 2026, требует Android 5.1 или новее), и `metadata/org.gnu.emacs.yml` собирает 31.1 (NDK r27d, четыре ABI). Расхождений между источниками нет; в метаданных видны и более старые линии сборки (30.0.50, 30.1, 30.2, 31.0.90, 31.0.91). |
| «`package.el` внутри приложения не работает (нет `tar`)» (§3) | Верно для стоковой сборки. При общем user ID бинарники Termux (`tar` в том числе) становятся доступны через общий `exec-path`/UID — но только в варианте A′. |
| Термин «shared user ID» | В Android это не то же самое, что package name: у Termux:API package name `com.termux.api`, а shared user ID у обоих `com.termux` (§10.2). Поэтому «shared user ID = package name терминала» из руководства верно только для основного приложения Termux. |

---

## 14. Что осталось непроверенным после второй волны

Ниже — не «не удалось найти», а «требует устройства»:

- собирается ли Emacs с `--with-shared-user-id=com.termux` и подписью `java/emacs.keystore`
  (нужны Android SDK/NDK на другой ОС; не проверялось);
- даёт ли общий user ID фактический доступ к `/data/data/com.termux/files/usr/bin/git` из
  процесса Emacs;
- ставится ли переподписанный Termux рядом со стоковым и что именно скажет установщик
  (ожидается `INSTALL_FAILED_SHARED_USER_INCOMPATIBLE` для стоковой пары);
- видно ли `exec-path` / `exec-directory` бинарники Termux из Emacs;
- работает ли `termux-exec` / `RunCommandService` из Emacs с совпадающим ключом;
- что происходит с общим каталогом данных при удалении одного из приложений группы;
- есть ли в сборке приложения доверенные сертификаты (TLS) — вопрос первой волны, не
  решён;
- совпадает ли фактический `TERMUX_PACKAGE_NAME` стоковой сборки Termux с `com.termux`
  (по манифесту и `build.gradle` — да; на устройстве не проверено).

---

## Источники

- <https://github.com/11111000000/yeah> — репозиторий (код, README, `install/yeah-bootstrap.el`).
- <https://github.com/termux/termux-packages/blob/master/packages/emacs/build.sh> — Emacs 31.1 в Termux.
- <https://github.com/termux/termux-api/blob/master/README.md> — ограничение вызовов API Termux подписью.
- <https://github.com/karthink/gptel/releases/tag/v0.9.9.6> — релиз gptel 0.9.9.6.
- <https://raw.githubusercontent.com/karthink/gptel/v0.9.9.6/gptel.el> — Package-Requires, `eval-and-compile` require.
- <https://raw.githubusercontent.com/karthink/gptel/v0.9.9.6/gptel-request.el> — `gptel-use-curl`, путь через `url-retrieve`.
- <https://f-droid.org/en/packages/org.gnu.emacs> — приложение Emacs для Android, версия 31.1, описание.

### Вторая волна (2026-11-19)

Руководство GNU Emacs, приложение H «Emacs and Android»:

- <https://www.gnu.org/software/emacs/manual/html_node/emacs/Android.html> — оглавление приложения.
- <https://www.gnu.org/software/emacs/manual/html_node/emacs/What-is-Android_003f.html> — H.1, что такое Android и позиция проекта Emacs.
- <https://www.gnu.org/software/emacs/manual/html_node/emacs/Android-Startup.html> — H.2, запуск приложения Emacs, `emacsclient`, логи.
- <https://www.gnu.org/software/emacs/manual/html_node/emacs/Android-File-System.html> — H.3, четыре каталога приложения, `exec-path`, Scoped storage.
- <https://www.gnu.org/software/emacs/manual/html_node/emacs/Android-Document-Providers.html> — H.4, доступ к каталогам провайдеров документов.
- <https://www.gnu.org/software/emacs/manual/html_node/emacs/Android-Environment.html> — H.5, окружение процесса, `libandroid-emacs.so`, `EMACS_CLASS_PATH`.
- <https://www.gnu.org/software/emacs/manual/html_node/emacs/Android-Software.html> — H.9, Termux, Busybox, termux-packages, MIME-база.

Дерево `java/` репозитория Emacs:

- <https://raw.githubusercontent.com/emacs-mirror/emacs/master/java/INSTALL> — «BUILDING WITH A SHARED USER ID» (`--with-shared-user-id`), «16 KB PAGE SIZES».
- <https://raw.githubusercontent.com/emacs-mirror/emacs/master/java/Makefile.in> — `SIGN_EMACS`, `SIGN_EMACS_V2`, генерация `emacs.keystore`.
- <https://raw.githubusercontent.com/emacs-mirror/emacs/master/java/AndroidManifest.xml.in> — `package="org.gnu.emacs"`, плейсхолдеры `@ANDROID_SHARED_USER_ID@`/`@ANDROID_SHARED_USER_NAME@`.
- <https://api.github.com/repos/emacs-mirror/emacs/contents/java> — состав каталога `java/`, наличие `emacs.keystore`.

Termux и Termux:API:

- <https://raw.githubusercontent.com/termux/termux-app/master/app/src/main/AndroidManifest.xml> — `android:sharedUserId`, `RunCommandService`, провайдеры `files`/`documents`, `MANAGE_EXTERNAL_STORAGE`.
- <https://raw.githubusercontent.com/termux/termux-app/master/app/build.gradle> — `TERMUX_PACKAGE_NAME = "com.termux"`, версия 0.118.0.
- <https://raw.githubusercontent.com/termux/termux-api/master/app/src/main/AndroidManifest.xml> — permission `sharedfiles.READ_WRITE` с `protectionLevel="signature"`.
- <https://raw.githubusercontent.com/termux/termux-api/master/app/build.gradle> — `namespace`/`applicationId` `com.termux.api` при `TERMUX_PACKAGE_NAME = "com.termux"`.

Сборка и подпись:

- <https://gitlab.com/fdroid/fdroiddata/-/raw/master/metadata/org.gnu.emacs.yml> — рецепт сборки 31.1 (NDK r27d, четыре ABI); shared user ID и keystore в метаданных не заданы.
- <https://gitlab.com/fdroid/fdroidserver/-/raw/master/fdroidserver/build.py> — сборка даёт неподписанный APK (`output_dir = 'unsigned'`).
- <https://gitlab.com/fdroid/fdroidserver/-/raw/master/fdroidserver/publish.py> — при публикации APK подписывается ключом репозитория (`config['keystore']`).
- <https://raw.githubusercontent.com/johanwiden/termux-for-android-emacs/main/README.md> — рецепт переподписи Termux ключом Emacs (`apksigner sign --v2-signing-enabled --ks emacs.keystore …`).

Сообщество:

- <https://raw.githubusercontent.com/zielmicha/emacs-android/master/README.md> — порт Emacs для Android и его сборка (`native/build.sh`).
- <https://raw.githubusercontent.com/zielmicha/emacs-android-app/master/README.md> — приложение-терминал с этим портом.
- <https://raw.githubusercontent.com/mariusk/android-with-emacs/master/README.md> — разработка Android-приложений из Emacs (`M-x compile`, `gradleMake`, `ggtags`).
- <https://raw.githubusercontent.com/jethrokuan/.emacs.d-android/master/README.md> — конфиги под Termux; в README помечены как архивированные и слитые с основными dotfiles.
- <https://api.github.com/search/repositories?q=emacs+android+in:name&sort=stars&per_page=10> — выборка репозиториев по словосочетанию «emacs android».
