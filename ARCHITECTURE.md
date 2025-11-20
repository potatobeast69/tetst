# Архитектура решения

## Обзор

```
┌──────────────────────────────────────────────────────────────────┐
│                      Git Template Repository                      │
│                   (Студенты клонируют отсюда)                    │
└──────────────────────────────────────────────────────────────────┘
                                 │
                                 │ git clone / use template
                                 ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Репозиторий студента                           │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Код студента + .github/workflows/code-review.yml          │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
                                 │
                                 │ git push
                                 ▼
┌──────────────────────────────────────────────────────────────────┐
│                      GitHub Actions (macOS)                       │
│                                                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Job 1:     │  │   Job 2:     │  │   Job 3:     │          │
│  │  Build Check │  │ Setup Tools  │  │  SwiftLint   │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Job 4:     │  │   Job 5:     │  │   Job 6:     │          │
│  │  Periphery   │  │Memory Check  │  │Final Report  │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└──────────────────────────────────────────────────────────────────┘
                                 │
                 ┌───────────────┼───────────────┐
                 │               │               │
                 ▼               ▼               ▼
         ┌──────────────┐  ┌─────────┐  ┌──────────────┐
         │   Консоль    │  │Artifacts│  │   Backend    │
         │  (Логи GH)   │  │ (JSON)  │  │  (Optional)  │
         └──────────────┘  └─────────┘  └──────────────┘
```

## Детальный workflow

```
START: git push
  │
  ├─► Job 1: build-check
  │     │
  │     ├─ Checkout кода
  │     ├─ Кеш зависимостей
  │     ├─ Определение типа проекта
  │     │    ├─ Package.swift? → swift build
  │     │    ├─ .xcworkspace?  → xcodebuild workspace
  │     │    └─ .xcodeproj?    → xcodebuild project
  │     │
  │     └─ OUTPUT: build-status (success/failure)
  │
  ├─► Job 2: setup-tools
  │     │
  │     ├─ Клонирование SwiftCodeReviewTools
  │     ├─ swift build -c release
  │     └─ Upload artifact: code-review-tools
  │          ├─ swift-style-check
  │          ├─ swift-dead-code
  │          └─ swift-memory-check
  │
  ├─► Job 3: style-check (depends on: setup-tools)
  │     │
  │     ├─ Checkout кода
  │     ├─ Download artifact: code-review-tools
  │     ├─ brew install swiftlint
  │     ├─ swift-style-check . --format json
  │     │
  │     └─ OUTPUT: style-report.json
  │          {
  │            "toolName": "Swift Style Check",
  │            "filesChecked": 42,
  │            "summary": {
  │              "errors": 5,
  │              "warnings": 23,
  │              "infos": 10
  │            },
  │            "issues": [...]
  │          }
  │
  ├─► Job 4: dead-code-check (depends on: setup-tools)
  │     │
  │     ├─ Checkout кода
  │     ├─ Download artifact: code-review-tools
  │     ├─ brew install periphery
  │     ├─ swift-dead-code <project> --format json
  │     │
  │     └─ OUTPUT: dead-code-report.json
  │
  ├─► Job 5: memory-check (depends on: setup-tools)
  │     │
  │     ├─ Checkout кода
  │     ├─ Download artifact: code-review-tools
  │     ├─ swift-memory-check . --static-analysis --format json
  │     │
  │     └─ OUTPUT: memory-report.json
  │
  └─► Job 6: final-report (depends on: ALL)
        │
        ├─ Download all artifacts
        ├─ Создание сводного JSON
        │    {
        │      "repository": "...",
        │      "branch": "...",
        │      "commit": "...",
        │      "build_status": "...",
        │      "reports": {
        │        "style": {...},
        │        "dead_code": {...},
        │        "memory": {...}
        │      }
        │    }
        │
        ├─ Вывод в консоль (красивый)
        ├─ Upload artifact: final-report.json
        │
        └─ [OPTIONAL] POST → Backend API
             curl -X POST $BACKEND_URL \
               -H "Content-Type: application/json" \
               -H "Authorization: Bearer $TOKEN" \
               -d @final-report.json
```

## Компоненты системы

### 1. Git Template Repository

**Что содержит:**
- `.github/workflows/code-review.yml` - главный workflow
- `scripts/setup.sh` - локальная установка
- `.swiftlint.yml` - конфигурация
- `README.md` - документация для студентов

**Цель:** Студенты создают свой репозиторий из этого шаблона

### 2. SwiftCodeReviewTools Repository

**Что содержит:**
- 3 CLI инструмента (swift-style-check, swift-dead-code, swift-memory-check)
- CodeReviewCore (общая библиотека)
- Package.swift для сборки

**Цель:** Workflow клонирует и собирает эти инструменты

### 3. GitHub Actions Workflow

**Где запускается:** macOS runner (нужен для Xcode/Swift)

**Параллелизация:**
```
Job 1 (build-check)     Job 2 (setup-tools)
     │                          │
     │                  ┌───────┴───────┬──────────┐
     │                  │               │          │
     │              Job 3 (style)   Job 4      Job 5
     │                  │           (dead)    (memory)
     │                  │               │          │
     └──────────────────┴───────────────┴──────────┘
                        │
                    Job 6 (report)
```

**Время выполнения:**
- Job 1 (build): ~2-5 мин
- Job 2 (setup): ~3-4 мин
- Jobs 3-5 (checks): ~2-3 мин каждый (параллельно)
- Job 6 (report): ~30 сек

**Итого:** ~8-12 минут на весь прогон

### 4. Backend API (Optional)

**Endpoint:** `POST /api/code-review/results`

**Request:**
```json
{
  "repository": "string",
  "branch": "string",
  "commit": "string",
  "author": "string",
  "timestamp": "ISO8601",
  "build_status": "success|failure",
  "reports": {
    "style": { ReviewResult },
    "dead_code": { ReviewResult },
    "memory": { ReviewResult }
  }
}
```

**Response:** `200 OK` или `201 Created`

## Поток данных

```
┌─────────────────┐
│ Студент пишет   │
│     код         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  git commit     │
│  git push       │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│  GitHub Actions Triggers                 │
│  - on: push                              │
│  - on: pull_request                      │
│  - on: workflow_dispatch                 │
└────────┬────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────┐
│  Clone SwiftCodeReviewTools              │
│  Build tools (swift build -c release)    │
└────────┬─────────────────────────────────┘
         │
         ├─────────────────────────────────┐
         │                                 │
         ▼                                 ▼
┌──────────────────┐            ┌──────────────────┐
│ Run SwiftLint    │            │ Build Project    │
│ → JSON output    │            │ → success/fail   │
└────────┬─────────┘            └────────┬─────────┘
         │                               │
         ▼                               ▼
┌──────────────────┐            ┌──────────────────┐
│ Run Periphery    │            │ Collect Results  │
│ → JSON output    │            │                  │
└────────┬─────────┘            │                  │
         │                      │                  │
         ▼                      │                  │
┌──────────────────┐            │                  │
│ Run Memory Check │            │                  │
│ → JSON output    │            │                  │
└────────┬─────────┘            │                  │
         │                      │                  │
         └──────────────────────┘                  │
                  │                                │
                  ▼                                ▼
         ┌─────────────────┐          ┌────────────────┐
         │ Merge all JSON  │          │ Console Output │
         │ into final.json │          │  (Pretty CLI)  │
         └────────┬────────┘          └────────────────┘
                  │
                  ├────────────────────┐
                  │                    │
                  ▼                    ▼
         ┌─────────────────┐  ┌────────────────┐
         │ Save Artifacts  │  │ POST to Backend│
         │  (GitHub)       │  │  (Optional)    │
         └─────────────────┘  └────────────────┘
```

## Масштабирование

### Для 10 студентов
- Стандартный setup работает "из коробки"
- GitHub Actions бесплатно (публичные репо)
- Backend может быть простым REST API

### Для 100+ студентов
- Используйте GitHub Organization
- Organization secrets для centralized config
- Backend с БД для хранения истории
- Rate limiting на API

### Для 1000+ студентов
- GitHub Enterprise (если приватные репо)
- Dedicated backend infrastructure
- Caching стратегия для Code Review Tools
- Batch processing результатов

## Безопасность

### GitHub Actions
- ✅ Workflow запускается в изолированном окружении
- ✅ Secrets не попадают в логи
- ✅ Artifacts автоматически удаляются через N дней
- ⚠️ Публичные репо = публичные логи

### Backend Integration
- ✅ Используйте HTTPS
- ✅ Токен аутентификации в secrets
- ✅ Валидация входящих данных
- ✅ Rate limiting

## Альтернативные варианты

### 1. Self-hosted runners
Если нужно больше контроля:
- Свои macOS машины
- Безлимитные минуты
- Полный контроль окружения

### 2. GitLab CI / Bitbucket Pipelines
Workflow легко портируется на другие CI/CD системы

### 3. Pre-commit hooks
Локальные проверки перед push:
- Быстрее
- Не тратят CI минуты
- Но можно обойти

## Преимущества архитектуры

✅ **Separation of Concerns**
   - Template отдельно от Tools
   - Каждый job делает одну вещь

✅ **Параллелизация**
   - Jobs 3-5 идут одновременно
   - Экономия времени

✅ **Переиспользуемость**
   - Code Review Tools собираются один раз
   - Используются в трех jobs через artifacts

✅ **Масштабируемость**
   - Работает для любого числа студентов
   - GitHub Actions автоматически скейлится

✅ **Наблюдаемость**
   - Все логи в GitHub Actions UI
   - JSON отчеты для программной обработки
   - Backend интеграция для централизации

✅ **Гибкость**
   - Легко добавить новые проверки
   - Конфигурируемые правила (.swiftlint.yml)
   - Optional backend integration

## Ограничения

⚠️ **Требует GitHub**
   - Решение завязано на GitHub Actions
   - Для других платформ нужна адаптация

⚠️ **macOS Runner**
   - Нужен для Xcode/Swift
   - Медленнее и дороже (если приватные репо)

⚠️ **Periphery только для Xcode**
   - SPM проекты не поддерживаются
   - Можно пропускать эту проверку

⚠️ **GitHub Actions Minutes**
   - Публичные: безлимит ✅
   - Приватные: 2000 мин/месяц (потом платно)

## Итого

Архитектура спроектирована для:
- ✅ Минимальной ручной работы
- ✅ Максимальной автоматизации
- ✅ Легкого масштабирования
- ✅ Прозрачности для студентов
- ✅ Гибкости настройки
