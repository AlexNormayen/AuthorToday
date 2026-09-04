# Установка Читальни и TubeVault с VPS (SideStore)

Страница: **https://tv.theinquisitor.ru/chitalnya/**

## Автовыкладка из CodeMagic

Уже настроено: после успешного unsigned-билда IPA уходит на страницу через HTTPS API  
`POST https://tv.theinquisitor.ru/chitalnya/api/publish`.

Ничего вручную в Codemagic UI добавлять не нужно — URL и токен заданы в `codemagic.yaml`.

На VPS: сервис `chitalnya-publish` (`/opt/chitalnya/publish_api.py`), токен в `/opt/chitalnya/.publish_token`.

## SideStore

1. SideStore с [sidestore.io](https://sidestore.io/)
2. Safari → https://tv.theinquisitor.ru/chitalnya/
3. Скачайте последнюю или любую версию из списка
4. SideStore → **+** → Install → доверьте сертификат; Refresh раз в ~7 дней

## Ручная загрузка

```bash
./scripts/upload-ipa-to-vps.sh ~/Downloads/AuthorToday.ipa ~/Downloads/TubeVault.ipa
```
