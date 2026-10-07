# APNs для Читальни — пошагово

Bundle ID: `ru.chitalnya.reader`  
Team ID: `57FVB8DUWX`

## Шаг 1. Apple Developer (делаете вы)

1. Откройте https://developer.apple.com/account/resources/identifiers/list  
2. Найдите App ID **ru.chitalnya.reader** → Edit.  
3. Включите **Push Notifications** → Save.  
4. Откройте https://developer.apple.com/account/resources/authkeys/list  
5. **+** → имя например `Chitalnya APNs` → галочка **Apple Push Notifications service (APNs)** → Continue → Register.  
6. Скачайте файл `.p8` (**один раз**), запишите **Key ID**.  
7. Profiles: обновите/пересоздайте App Store + Development profiles для `ru.chitalnya.reader` (чтобы подтянули Push).

## Шаг 2. Ключ на VPS (делаете вы или скиньте Key ID + файл)

На сервере:

```bash
# положить скачанный файл:
#   /opt/chitalnya/AuthKey_XXXXXXXXXX.p8
# или скопировать как:
#   /opt/chitalnya/AuthKey_APNs.p8

cat >/opt/chitalnya/.notify_env <<'EOF'
APNS_KEY_ID=ВАШ_KEY_ID
APNS_TEAM_ID=57FVB8DUWX
APNS_BUNDLE_ID=ru.chitalnya.reader
APNS_KEY_PATH=/opt/chitalnya/AuthKey_APNs.p8
NOTIFY_POLL_SECONDS=45
EOF
chmod 600 /opt/chitalnya/.notify_env /opt/chitalnya/AuthKey_APNs.p8

python3 -m pip install -q 'PyJWT' 'cryptography' 'httpx[http2]'
systemctl restart chitalnya-notify
curl -sS https://at.theinquisitor.ru/chitalnya/api/notify-health
# ожидаем: "apnsConfigured": true
```

## Шаг 3. Приложение (уже в коде)

- Entitlement `aps-environment = production`
- Background mode `remote-notification`
- Регистрация device token → VPS `/notify-device`
- В приложении: **Ещё → Быстрый опрос через VPS** (нужен и для пушей: на VPS должен быть AT-токен)

После этого нужна **новая сборка** (Codemagic / Xcode) и установка на устройство.

## Шаг 4. Проверка

1. Включить «Быстрый опрос через VPS».  
2. Статус не должен ругаться на APNs.  
3. Вызвать тестовый пуш с VPS (после регистрации токена):

```bash
# посмотреть токены:
sqlite3 /opt/chitalnya/notify.db 'select user_id, substr(device_token,1,16), environment from device_tokens;'
```

4. Закрыть приложение полностью → дождаться нового события на Author.Today (или подождать опрос ~45 с после реального уведомления AT).

## Важно

- TestFlight / App Store → environment **production** (так шлёт сборка).  
- Локальный Debug из Xcode без APPSTORE → **sandbox**; для него нужен тот же `.p8`, URL sandbox (приложение само помечает `environment=sandbox`).  
- Без шагов 1–2 пуши не уйдут; delta-опрос при открытом приложении продолжит работать.
