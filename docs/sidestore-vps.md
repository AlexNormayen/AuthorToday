# Установка Читальни и TubeVault с VPS (SideStore)

Страница: **https://tv.theinquisitor.ru/chitalnya/**

## Что это

На VPS лежат unsigned IPA:

- **Читальня** (`AuthorToday.ipa`) — клиент Author.Today
- **TubeVault** (`TubeVault.ipa`) — клиент облачной полки / сервиса

Ставите сами через **SideStore** на iPhone/iPad или **Sideloadly** на ПК. Apple Developer не нужен. Подпись бесплатным Apple ID действует ~7 дней — потом Refresh в SideStore.

## SideStore (на устройстве)

1. Один раз поставьте SideStore по инструкции с [sidestore.io](https://sidestore.io/) (нужен ПК).
2. На iPhone/iPad откройте в Safari: https://tv.theinquisitor.ru/chitalnya/
3. Скачайте нужный IPA
4. SideStore → **+** → выберите IPA → Install
5. Настройки → Основные → VPN и управление устройством → доверьте сертификат

## Как обновить IPA на сервере

```bash
# оба сразу (Git Bash / WSL / macOS / Linux)
./scripts/upload-ipa-to-vps.sh ~/Downloads/AuthorToday.ipa ~/Downloads/TubeVault.ipa

# или по одному
./scripts/upload-ipa-to-vps.sh --app chitalnya ~/Downloads/AuthorToday.ipa
./scripts/upload-ipa-to-vps.sh --app tubevault ~/Downloads/TubeVault.ipa
```

Или вручную по SSH:

```bash
scp -i ~/.ssh/id_ed25519_aeza AuthorToday.ipa TubeVault.ipa root@185.125.103.168:/opt/chitalnya/
```

После загрузки страница покажет размер и дату (`meta.json`).

## Sideloadly

Тот же IPA со страницы → Sideloadly на Windows/Mac → USB.
