# AuthorToday

Неофициальный iOS-клиент для [author.today](https://author.today): библиотека, читалка, офлайн и оповещения.

Целевое устройство: **iPhone 15 Pro Max** (iOS 17+). Стек: **SwiftUI**.

Репозиторий: https://github.com/AlexNormayn/AuthorToday

## Сборка IPA без Mac — Codemagic

GitHub Actions на этом аккаунте заблокированы (`Unable to enable Actions`). Сборка идёт через **Codemagic**.

### 1. Зарегистрироваться

1. Откройте https://codemagic.io/signup  
2. Войдите через **GitHub** (аккаунт AlexNormayn)  
3. Разрешите доступ к репозиторию **AuthorToday** (или ко всем public)

### 2. Добавить приложение

1. Codemagic → **Applications** → **Add application**  
2. Team: Personal  
3. Repository: `AlexNormayn/AuthorToday`  
4. Project type: **Swift / Objective-C** (или «detect from codemagic.yaml»)  
5. Finish / Select repository

Codemagic подхватит файл `codemagic.yaml` в корне.

### 3. Запустить сборку

1. Откройте приложение AuthorToday в Codemagic  
2. Workflow: **AuthorToday iOS IPA (unsigned)**  
3. **Start new build** → ветка `main`  
4. Дождитесь успеха (обычно 10–20 мин)

### 4. Скачать IPA

В завершённом билде → **Artifacts** → `AuthorToday.ipa`

### 5. Установить на iPhone (Windows)

1. [Sideloadly](https://sideloadly.io/)  
2. iPhone по USB  
3. IPA + бесплатный Apple ID → Start  
4. На iPhone: **Настройки → Основные → VPN и управление устройством** → доверить

Подпись ~7 дней, потом переподпись тем же IPA.

> Платный Apple Developer не нужен для личного устройства.

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
codemagic.yaml     — облачная сборка IPA
.github/workflows/ — запасной workflow (если Actions разблокируют)
```

API: `https://api.author.today`  
Расшифровка глав: `ChapterDecryptor` (`Reader-Secret`).

## Если билд упал в Codemagic

- Откройте лог шага **Build without code signing**
- Пришлите ошибку — поправим код и запушим снова
