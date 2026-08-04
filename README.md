# AuthorToday

Неофициальный iOS-клиент для [author.today](https://author.today): библиотека, читалка, офлайн и оповещения.

Целевое устройство: **iPhone 15 Pro Max** (iOS 17+). Стек: **SwiftUI**.

## Установка без Mac (GitHub Actions + Sideloadly)

Да — Swift оставляем. IPA собирается **бесплатно** на `macos-14` runner в GitHub Actions. На телефон ставите с Windows через Sideloadly.

### 1. Залить репозиторий на GitHub

```powershell
cd $env:USERPROFILE\Projects\AuthorToday
git add .
git commit -m "Initial AuthorToday iOS app"
# создайте пустой репозиторий на github.com, затем:
git remote add origin https://github.com/ВАШ_ЛОГИН/AuthorToday.git
git branch -M main
git push -u origin main
```

Публичный репозиторий удобнее: больше бесплатных минут macOS. В приватном лимит жёстче (~200 мин macOS/мес на free-плане).

### 2. Собрать IPA

1. GitHub → вкладка **Actions**
2. Workflow **Build iOS IPA** → **Run workflow**
3. Дождаться зелёной галочки (5–15 мин)
4. В артефактах скачать **AuthorToday-ipa** → внутри `AuthorToday.ipa`

### 3. Поставить на iPhone (Windows)

1. Установите [Sideloadly](https://sideloadly.io/)
2. iPhone по USB, доверьте компьютеру
3. В Sideloadly: IPA + ваш **бесплатный Apple ID** → Start
4. На iPhone: **Настройки → Основные → VPN и управление устройством** → доверить разработчику

Подпись живёт **~7 дней**. Потом снова Sideloadly с тем же IPA (или новой сборкой).

> Платный Apple Developer ($99) не нужен для личного устройства. App Store / TestFlight / remote push — только с ним.

## Что умеет

- Вход по email/паролю (API author.today)
- Библиотека + синхронизация
- Поиск / свежие книги
- Читалка: скролл, свайп, тап по зонам, тап+свайп, перелистывание
- Настройки шрифта, фона, отступов; свой фон из Фото
- Автоскачивание при первом открытии (офлайн SwiftData)
- Оповещения: опрос API + локальные уведомления

## Архитектура

```
AuthorToday/
  Models/          — DTO + SwiftData
  Services/        — API, auth, offline, download, notifications
  Views/           — Login, Library, Search, Notifications, Reader
.github/workflows/ — сборка IPA на GitHub Actions
```

API: `https://api.author.today`  
Расшифровка глав: `ChapterDecryptor` (заголовок `Reader-Secret`).

## Если сборка в Actions упала

- Откройте лог job «Build (no code signing)»
- Часто чинится правкой Swift под актуальный SDK runner’а
- Перезапустите workflow после push

## Дальше (по желанию)

- Точная пагинация через TextKit
- BGAppRefresh для оповещений
- Remote push после платного Apple Developer
