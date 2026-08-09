# App Store — Читальня (трек B)

## Разрешение Author.Today

**Дата:** 8 августа 2026 (личное сообщение на author.today)  
**От:** Иннокентий | AuthorToday (после согласования с руководством проекта)  
**Кому:** Кавешников Александр Владимирович / @dark_tarkhan  

**Суть ответа (дословно по смыслу):** можно использовать API и распространять приложение указанными способами (в т.ч. App Store), **строго необходимо** чёткое предупреждение пользователям, что приложение **не является официальным**.

Скрин/копия переписки хранится у разработчика. Сабмит в Review при наличии этого OK и оплаченного Apple Developer Program.

## Идентификаторы

| Поле | Значение |
|------|----------|
| Name (под иконкой / Connect) | Читальня |
| Subtitle (полная формулировка) | Клиент Author.Today (неофициальный) |
| Subtitle в Connect (лимит 30 символов) | `Клиент Author.Today (неофиц.)` |
| Bundle ID | `ru.chitalnya.reader` |
| Категория | Books |
| Privacy Policy URL | хостинг `docs/privacy.html` (GitHub Pages / свой URL) |

Полную фразу «Клиент Author.Today (неофициальный)» ставим в **Promotional Text / первую строку Description** и в UI приложения; в поле Subtitle Connect — укороченный вариант из‑за лимита 30.

## App Store Connect — листинг

**Name:** Читальня  

**Subtitle:** `Клиент Author.Today (неофиц.)`  

**Description (черновик):**

```
Клиент Author.Today (неофициальный).

Читальня — независимый клиент для чтения книг с портала Author.Today.
Приложение не является официальным продуктом Author.Today и не связано с порталом.
Author.Today не отвечает за работу этого клиента.

• Вход в ваш аккаунт Author.Today
• Библиотека, поиск, читалка и офлайн-кэш
• Локальные оповещения о обновлениях
• Покупка книг только на официальном сайте author.today
• Опционально: «Читальня Pro» (темы, расширенный офлайн, свои TXT/EPUB) — через Apple IAP;
  это оплата удобств клиента, не книг портала
```

**Keywords:** чтение, книги, библиотека, офлайн, фэнтези, litrpg (без «официальный Author.Today»).

**В листинге не афишировать:** темы «Сорвиголова» и т.п. (остаются в приложении; премиум-темы — в Pro).

## In-App Purchase — Читальня Pro

Создать в App Store Connect (группа подписок **Chitalnya Pro**):

| Product ID | Тип | Назначение |
|------------|-----|------------|
| `ru.chitalnya.reader.pro.monthly` | Auto-renewable | Pro на месяц |
| `ru.chitalnya.reader.pro.yearly` | Auto-renewable | Pro на год |
| `ru.chitalnya.reader.pro.lifetime` | Non-Consumable | Pro навсегда |

Локальный каталог для отладки: `AuthorToday/Products.storekit` (подключить в Scheme → Run → StoreKit Configuration).

**Free:** классические темы (Мох/Океан/Вино/Графит/Песок), чтение, синхрон, кэш открытых глав, до **2** книг «скачать все главы».  
**Pro:** futuristic + фото-темы + свой цвет приложения; безлимитный full-download; «Перелистывание»; свой цвет/картинка фона читалки; **«Мои книги»** — импорт своих TXT/EPUB (только на устройстве, без синка с Author.Today).

## Review Notes (вставить в Connect)

```
Неофициальный клиент публичного API Author.Today (api.author.today).
Письменное разрешение Author.Today (август 2026): можно использовать API и распространять
приложение при обязательном предупреждении, что оно не официальное.

Вход: email/пароль аккаунта Author.Today.
Если у аккаунта включено подтверждение устройства — после пароля приложение запрашивает код из письма Author.Today.

Покупки книг открывают официальный сайт author.today (WebView).
Отдельно: подписка / lifetime «Читальня Pro» через Apple IAP — только удобства клиента
(темы, офлайн-лимит, режимы читалки, локальные TXT/EPUB). Pro НЕ продаёт и НЕ разблокирует книги Author.Today.

Демо-аккаунт: [вставить логин/пароль тестового AT-аккаунта для ревьюеров].
```

## Шифрование

В билде: `ITSAppUsesNonExemptEncryption = NO` (только HTTPS). В Connect при вопросе про encryption — указать exempt / standard HTTPS.

## Что нужно перед сабмитом

1. ~~Ответ support@author.today~~ — получено (см. выше).
2. Apple Developer Program оплачен → **Team ID** из Membership.
3. В App Store Connect создать приложение с bundle `ru.chitalnya.reader`.
4. В Codemagic: App Store Connect API key + сертификаты для workflow `ios-app-store-signed`.
5. Скриншоты iPhone 6.7" (логин с дисклеймером / библиотека / читалка).
6. Публичный URL Privacy Policy (`docs/privacy.html`).
7. TestFlight → Submit for Review.
