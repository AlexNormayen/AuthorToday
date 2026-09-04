# Установка Читальни и TubeVault с VPS (SideStore)

Страница: **https://tv.theinquisitor.ru/chitalnya/**

## Что это

На VPS хранятся unsigned IPA и **история сборок**:

- **Читальня** (`AuthorToday.ipa`) — клиент Author.Today
- **TubeVault** (`TubeVault.ipa`) — клиент облачной полки / сервиса

Можно скачать последнюю или любую прошлую версию. Ставите через **SideStore** на iPhone/iPad или **Sideloadly** на ПК. Apple Developer не нужен. Подпись бесплатным Apple ID действует ~7 дней — потом Refresh в SideStore.

После успешной сборки **CodeMagic** IPA заливается на страницу автоматически (если настроены env vars ниже).

## SideStore (на устройстве)

1. Один раз поставьте SideStore по инструкции с [sidestore.io](https://sidestore.io/) (нужен ПК).
2. На iPhone/iPad откройте в Safari: https://tv.theinquisitor.ru/chitalnya/
3. Скачайте нужный IPA (последняя или выбранная версия)
4. SideStore → **+** → выберите IPA → Install
5. Настройки → Основные → VPN и управление устройством → доверьте сертификат

## Автовыкладка из CodeMagic

В Codemagic → приложение → **Environment variables** (для unsigned workflow):

| Variable | Secure | Значение |
|---|---|---|
| `CHITALNYA_SSH_KEY` | да | содержимое приватного ключа `~/.ssh/id_ed25519_aeza` (имя с суффиксом `_SSH_KEY` — ключ попадёт в ssh-agent) |
| `CHITALNYA_VPS_HOST` | нет | `root@185.125.103.168` |

Сделать в **обоих** проектах: AuthorToday и TubeVault.

После следующего успешного unsigned-билда версия появится на странице как `b{N}-{commit}`.

## Ручная загрузка

```bash
# AuthorToday repo — оба или по одному (история версий сохраняется)
./scripts/upload-ipa-to-vps.sh ~/Downloads/AuthorToday.ipa ~/Downloads/TubeVault.ipa

# или напрямую
./scripts/publish-ipa-version.sh --app chitalnya --sync-page ~/Downloads/AuthorToday.ipa
./scripts/publish-ipa-version.sh --app tubevault ~/Downloads/TubeVault.ipa
```

Структура на сервере: `/opt/chitalnya/builds/{chitalnya|tubevault}/{versionId}/*.ipa` + корневые latest-копии.

## Sideloadly

Тот же IPA со страницы → Sideloadly на Windows/Mac → USB.
