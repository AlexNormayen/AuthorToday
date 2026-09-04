# Установка Читальни с VPS (SideStore)

Страница: **https://tv.theinquisitor.ru/chitalnya/**

## Что это

На VPS лежит свежий `AuthorToday.ipa` (unsigned из CodeMagic). Вы ставите его сами через **SideStore** на iPhone/iPad или через **Sideloadly** на ПК.

Apple Developer для этого не нужен. Подпись бесплатным Apple ID действует ~7 дней — потом Refresh в SideStore.

## SideStore (на устройстве)

1. Один раз поставьте SideStore по инструкции с [sidestore.io](https://sidestore.io/) (нужен ПК).
2. На iPhone/iPad откройте в Safari: https://tv.theinquisitor.ru/chitalnya/
3. Скачайте **AuthorToday.ipa**
4. SideStore → **+** → выберите IPA → Install
5. Настройки → Основные → VPN и управление устройством → доверьте сертификат

## Как обновить IPA на сервере

После сборки CodeMagic скачайте артефакт `AuthorToday.ipa` и залейте:

```bash
# из Git Bash / WSL / macOS / Linux
./scripts/upload-ipa-to-vps.sh ~/Downloads/AuthorToday.ipa
```

Или вручную по SSH:

```bash
scp -i ~/.ssh/id_ed25519_aeza AuthorToday.ipa root@185.125.103.168:/opt/chitalnya/AuthorToday.ipa
```

После загрузки страница сама покажет размер и дату (файл `meta.json`).

## Sideloadly

Тот же IPA с страницы → Sideloadly на Windows/Mac → USB.
