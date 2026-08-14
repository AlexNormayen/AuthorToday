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

**Free:** классические темы (Мох/Океан/Вино/Графит/Песок + спокойные), чтение, синхрон, кэш открытых глав, до **2** книг «скачать все главы», виджет «Продолжить чтение».  
**Pro:** futuristic + фото-темы + свой цвет приложения; безлимитный full-download; закладки/заметки (только устройство); «Перелистывание»; свой цвет/картинка фона читалки; **«Мои книги»** — импорт своих TXT/EPUB (только на устройстве, без синка с Author.Today).

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

## Пошагово: от письма Apple до TestFlight

### 1. Дозавершить enrollment
1. В письме Apple Developer нажать **Complete your enrollment now**.
2. Войти тем же Apple ID, оплатить программу (~$99/год).
3. Дождаться статуса **Active** на [developer.apple.com/account](https://developer.apple.com/account) → Membership.
4. Скопировать **Team ID** (10 символов) — понадобится в Codemagic.

### 2. Agreements в App Store Connect
1. Открыть [appstoreconnect.apple.com](https://appstoreconnect.apple.com).
2. Agreements, Tax, and Banking — принять **Paid Applications**, заполнить налоговые/банковские данные (нужно для IAP Pro).
3. Без этого In-App Purchase и платные билды не заработают.

### 3. Приложение и Bundle ID
1. Certificates, Identifiers & Profiles → Identifiers → создать App ID `ru.chitalnya.reader` (если ещё нет), с capabilities: In-App Purchase.
2. App Store Connect → My Apps → **+** → New App:
   - Platform: iOS
   - Name: **Читальня**
   - Bundle ID: `ru.chitalnya.reader`
   - SKU: например `chitalnya-reader-1`
   - Access: Full Access

### 4. In-App Purchase (Читальня Pro)
Создать продукты (см. таблицу выше):
- `ru.chitalnya.reader.pro.monthly`
- `ru.chitalnya.reader.pro.yearly`
- `ru.chitalnya.reader.pro.lifetime`

Для подписок: создать Subscription Group **Chitalnya Pro**, привязать month/year.  
Для lifetime — Non-Consumable.  
Цены и локализации (RU) — в Connect. После создания продукты должны быть в статусе **Ready to Submit** вместе с билдом.

### 5. Подпись и Codemagic
1. В Codemagic → приложение AuthorToday → workflow **`ios-app-store-signed`**.
2. Environment variables: `DEVELOPMENT_TEAM` = Team ID.
3. Подключить **App Store Connect API key** (Users and Access → Keys → App Store Connect API) и сертификаты/профили (или automatic code signing через integration).
4. Запустить билд → артефакт уйдёт в TestFlight (если настроен upload).

Альтернатива без Codemagic: собрать Archive в Xcode на Mac с тем же Team ID и Upload to App Store Connect.

### 6. Листинг и Review
1. Заполнить Name / Subtitle / Description / Keywords (черновик выше).
2. Privacy Policy URL (задеплоить `docs/privacy.html`).
3. Скриншоты 6.7" (логин с дисклеймером «неофициальный», библиотека, читалка).
4. Age Rating, App Privacy (данные логина AT — указать честно).
5. Review Notes (шаблон выше) + демо-аккаунт AT.
6. Выбрать билд из TestFlight → **Submit for Review**.

### 7. TestFlight (до сабмита в Review)
1. Users and Access → добавить себя / тестеров как Internal.
2. Дождаться обработки билда (Processing → Ready to Test).
3. Установить через TestFlight, проверить вход AT и покупку Pro (Sandbox Apple ID).

## Оплата Pro

Временная оплата через СБП **убрана**. Pro продаётся только через **Apple In-App Purchase** (StoreKit 2). Промокоды в UI остаются опционально.

### Intro offer и Family Sharing (Connect)

1. **Introductory offer** на `ru.chitalnya.reader.pro.yearly` (и при желании monthly):  
   App Store Connect → подписка → Introductory Offers → free trial или pay-up-front/pay-as-you-go.  
   Приложение само покажет intro-цену, если StoreKit её отдаст.
2. **Family Sharing** для auto-renewable подписок: в Subscription Group включить Share with Family.  
   Lifetime (non-consumable) шарится отдельно через «Family Sharing» на продукте, если включите.
3. После изменений дождитесь Ready to Submit и привяжите к билду.

### App Group (виджет «Продолжить»)

В Identifiers создать App Group `group.ru.chitalnya.reader` и включить его у:
- `ru.chitalnya.reader`
- `ru.chitalnya.reader.ContinueReadingWidget`

В коде: `AuthorToday.entitlements` и `ContinueReadingWidget.entitlements`. Deep link: `chitalnya://resume/{workId}?chapter=…`.

## Что нужно перед сабмитом

1. ~~Ответ support@author.today~~ — получено (см. выше).
2. Apple Developer Program оплачен → **Team ID** из Membership.
3. В App Store Connect создать приложение с bundle `ru.chitalnya.reader`.
4. В Codemagic: App Store Connect API key + сертификаты для workflow `ios-app-store-signed`.
5. Скриншоты iPhone 6.7" (логин с дисклеймером / библиотека / читалка).
6. Публичный URL Privacy Policy (`docs/privacy.html`).
7. IAP продукты созданы + банковские agreements.
8. TestFlight → Submit for Review.
