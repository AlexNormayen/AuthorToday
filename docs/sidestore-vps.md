# Установка Читальни и TubeVault с VPS (SideStore)

Страница: **https://tv.theinquisitor.ru/chitalnya/**

## Что это

На VPS хранятся unsigned IPA и **история сборок**:

- **Читальня** (`AuthorToday.ipa`) — клиент Author.Today
- **TubeVault** (`TubeVault.ipa`) — клиент облачной полки / сервиса

Можно скачать последнюю или любую прошлую версию. Ставите через **SideStore** / **Sideloadly**.

После успешной сборки **CodeMagic** IPA заливается на страницу **автоматически** (HTTPS API, без ручных env в UI).

## SideStore

1. Один раз поставьте SideStore с [sidestore.io](https://sidestore.io/)
2. Safari → https://tv.theinquisitor.ru/chitalnya/
3. Скачайте IPA (последняя или выбранная версия)
4. SideStore → **+** → Install
5. Доверьте сертификат в Настройках; раз в ~7 дней Refresh

## Автовыкладка

В `codemagic.yaml` уже заданы `CHITALNYA_PUBLISH_URL` и `CHITALNYA_PUBLISH_TOKEN`.  
Post-publish после успешного unsigned-билда делает `curl` multipart на `/chitalnya/api/publish`.

Сервис на VPS: `chitalnya-publish.service` (`/opt/chitalnya/publish_api.py`).  
Токен: `/opt/chitalnya/.publish_token` (должен совпадать с yaml).

## Ручная загрузка

```bash
./scripts/upload-ipa-to-vps.sh ~/Downloads/AuthorToday.ipa ~/Downloads/TubeVault.ipa
# или
./scripts/publish-ipa-version.sh --app chitalnya --sync-page ~/Downloads/AuthorToday.ipa
```

Структура: `/opt/chitalnya/builds/{chitalnya|tubevault}/{versionId}/*.ipa`
