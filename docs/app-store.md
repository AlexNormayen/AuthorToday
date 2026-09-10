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
| Widget Bundle ID | `ru.chitalnya.reader.ContinueReadingWidget` |
| App Group | `group.ru.chitalnya.reader` |
| Team ID | `57FVB8DUWX` |
| Категория | Books |
| Privacy Policy URL | `https://tv.theinquisitor.ru/chitalnya/privacy.html` (файл: `docs/privacy.html` / `docs/chitalnya-install/privacy.html`) |

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

Создать в App Store Connect (группа подписок **Chitalnya Pro**). Цены = бывший SBP:

| Product ID | Тип | Срок | Цена (₽) |
|------------|-----|------|----------|
| `ru.chitalnya.reader.pro.weekly` | Auto-renewable | 1 неделя | **149** |
| `ru.chitalnya.reader.pro.monthly` | Auto-renewable | 1 месяц | **349** |
| `ru.chitalnya.reader.pro.yearly` | Auto-renewable | 1 год | **2990** (launch-промо; ≈ −29% к 12×месяц) |

Lifetime / навсегда — **нет**.  
Локальный каталог: `AuthorToday/Products.storekit` (Scheme → Run → StoreKit Configuration).

**Free:** классические темы (Мох/Океан/Вино/Графит/Песок + спокойные), чтение, синхрон, кэш открытых глав, до **2** книг «скачать все главы», виджет «Продолжить чтение».  
**Pro:** futuristic + фото-темы + свой цвет приложения; безлимитный full-download; закладки/заметки (только устройство); «Перелистывание»; свой цвет/картинка фона читалки; **«Мои книги»** — TXT/EPUB без лимита (бесплатно 1 файл; после удаления повтор через 14 дней; только на устройстве, без синка с Author.Today).

## Review Notes (вставить в Connect)

```
Неофициальный клиент публичного API Author.Today (api.author.today).
Письменное разрешение Author.Today (август 2026): можно использовать API и распространять
приложение при обязательном предупреждении, что оно не официальное.

Вход: email/пароль аккаунта Author.Today.
Если у аккаунта включено подтверждение устройства — после пароля приложение запрашивает код из письма Author.Today.

Покупки книг открывают официальный сайт author.today (WebView).
Отдельно: подписка «Читальня Pro» через Apple IAP — только удобства клиента
(темы, офлайн-лимит, режимы читалки, локальные TXT/EPUB). Pro НЕ продаёт и НЕ разблокирует книги Author.Today.

Демо-аккаунт: [вставить логин/пароль тестового AT-аккаунта для ревьюеров].
```

## Шифрование

В билде: `ITSAppUsesNonExemptEncryption = NO` (только HTTPS). В Connect при вопросе про encryption — указать exempt / standard HTTPS.

## Пошагово: от письма Apple до TestFlight

### 1. Enrollment — готово
1. ~~Complete enrollment / оплата~~ — Membership **Active**.
2. **Team ID:** `57FVB8DUWX` (Membership на developer.apple.com).
3. В Codemagic → workflow **Читальня App Store (signed)** → Environment variables:  
   `DEVELOPMENT_TEAM` = `57FVB8DUWX`  
   (то же значение уже в `project.pbxproj` для Xcode).

### 2. Agreements в App Store Connect
1. Открыть [appstoreconnect.apple.com](https://appstoreconnect.apple.com).
2. Agreements, Tax, and Banking — принять **Paid Applications**, заполнить налоговые/банковские данные (нужно для IAP Pro).
3. Без этого In-App Purchase и платные билды не заработают.

### 3. Приложение и Bundle ID
1. Certificates, Identifiers & Profiles → Identifiers:
   - App ID `ru.chitalnya.reader` — capabilities: **In-App Purchase**, **App Groups** (`group.ru.chitalnya.reader`).
   - App ID `ru.chitalnya.reader.ContinueReadingWidget` — **App Groups** (тот же group).
2. App Store Connect → My Apps → **+** → New App:
   - Platform: iOS
   - Name: **Читальня**
   - Bundle ID: `ru.chitalnya.reader`
   - SKU: например `chitalnya-reader-1`
   - Access: Full Access

### 4. In-App Purchase (Читальня Pro)
Создать Subscription Group **Chitalnya Pro** и три auto-renewable (см. таблицу выше): week / month / year.  
Цены и локализации (RU) — в Connect. Статус **Ready to Submit** вместе с билдом.

### 5. Подпись и Codemagic
1. В Codemagic → приложение AuthorToday → workflow **`ios-app-store-signed`** (Читальня App Store).
2. Environment variables: `DEVELOPMENT_TEAM` = `57FVB8DUWX`.
3. Подключить **App Store Connect API key** (Users and Access → Keys → App Store Connect API) и сертификаты/профили (или automatic code signing через integration).
4. Запустить билд → артефакт `Chitalnya.ipa`; при настроенном API key — upload в TestFlight.
5. Сборка ставит `APPSTORE` + `ChitalnyaDistribution=appstore` (без SideStore-обновлений, Book Vault opt-in, без promo в Release).

Альтернатива без Codemagic: Archive в Xcode на Mac с Team `57FVB8DUWX` → Upload to App Store Connect.

### 6. Листинг и Review
1. Заполнить Name / Subtitle / Description / Keywords (черновик выше).
2. Privacy Policy URL: **`https://tv.theinquisitor.ru/chitalnya/privacy.html`**  
   (задеплоить `docs/chitalnya-install/privacy.html` на VPS рядом с install page, если ещё не лежит).
3. Скриншоты 6.7" (логин с дисклеймером «неофициальный», библиотека, читалка).
4. Age Rating, App Privacy (логин AT; опциональная облачная полка — только если пользователь включил).
5. Review Notes (шаблон выше) + демо-аккаунт AT.
6. Выбрать билд из TestFlight → **Submit for Review**.

### 7. TestFlight (до сабмита в Review)
1. Users and Access → добавить себя / тестеров как Internal.
2. Дождаться обработки билда (Processing → Ready to Test).
3. Установить через TestFlight, проверить вход AT и покупку Pro (Sandbox Apple ID).

## Оплата Pro

Временная оплата через СБП **убрана**. Pro продаётся только через **Apple In-App Purchase** (StoreKit 2).  
Промокоды / complimentary allowlist в **Release и App Store отключены** (остаются только в DEBUG).

### Intro offer и Family Sharing (Connect)

1. **Introductory offer** на `ru.chitalnya.reader.pro.yearly` (и при желании month/week):  
   App Store Connect → подписка → Introductory Offers → free trial или pay-up-front/pay-as-you-go.  
   Приложение само покажет intro-цену, если StoreKit её отдаст.
2. **Family Sharing** для auto-renewable: в Subscription Group включить Share with Family.
3. После изменений дождитесь Ready to Submit и привяжите к билду.

### App Group (виджет «Продолжить»)

В Identifiers создать App Group `group.ru.chitalnya.reader` и включить его у:
- `ru.chitalnya.reader`
- `ru.chitalnya.reader.ContinueReadingWidget`

В коде: `AuthorToday.entitlements` и `ContinueReadingWidget.entitlements`. Deep link: `chitalnya://resume/{workId}?chapter=…`.

## Чеклист перед первым TestFlight

1. ~~Разрешение Author.Today~~ — есть.
2. ~~Team ID~~ — `57FVB8DUWX` → Codemagic `DEVELOPMENT_TEAM`.
3. Paid Apps + Tax/Banking в App Store Connect.
4. Identifiers: main + widget + App Group + IAP.
5. New App «Читальня» в Connect.
6. IAP products Ready to Submit.
7. Privacy URL живой: `https://tv.theinquisitor.ru/chitalnya/privacy.html`.
8. Codemagic: secrets для **unsigned** publish (`CHITALNYA_SSH_KEY_B64` / `CHITALNYA_PUBLISH_TOKEN`) — только в UI, не в git.
9. Запуск workflow **Читальня App Store (signed)** → TestFlight.
10. Скриншоты 6.7" + Review Notes + демо AT-аккаунт → Submit for Review.

## Каналы сборки (код)

| Канал | Как | Обновления IPA | Book Vault | Pro promo |
|-------|-----|----------------|------------|-----------|
| Sideload | unsigned Codemagic / Xcode без `APPSTORE` | да | default on | только DEBUG |
| App Store | signed workflow / `APPSTORE` | нет | default off, opt-in | только DEBUG |
