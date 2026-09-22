# Установка Читальни и TubeVault с VPS (SideStore)

Страница: **https://at.theinquisitor.ru/chitalnya/**

Хост: **`132.243.119.95`** (`fowl348.fvds.ru`), домен **`at.theinquisitor.ru`** (HTTPS / Let's Encrypt).

## Автовыкладка из CI / CodeMagic

После успешного unsigned-билда IPA уходит на страницу через HTTPS API  
`POST https://at.theinquisitor.ru/chitalnya/api/publish`  
или SSH `chitalnya-publish@HOST` → `publish …` (stdin = IPA).

Секреты GitHub Actions: `CHITALNYA_VPS_HOST=132.243.119.95`, `CHITALNYA_SSH_KEY`, `CHITALNYA_PUBLISH_TOKEN`, `CHITALNYA_SSH_USER=chitalnya-publish`.

На VPS: сервис `chitalnya-publish` (`/opt/chitalnya/publish_api.py`), токен в `/opt/chitalnya/.publish_token`.  
TubeVault: `tubevault.service` на `:8787`, nginx vhost `at.theinquisitor.ru`.

## SideStore

1. SideStore с [sidestore.io](https://sidestore.io/)
2. Safari → https://at.theinquisitor.ru/chitalnya/
3. Скачайте последнюю или любую версию из списка
4. SideStore → **+** → Install → доверьте сертификат; Refresh раз в ~7 дней

## Ручная загрузка

```bash
./scripts/upload-ipa-to-vps.sh ~/Downloads/AuthorToday.ipa ~/Downloads/TubeVault.ipa
```
