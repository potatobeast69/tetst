#!/bin/bash

# Скрипт установки зависимостей для Code Review
# Используется студентами для локальной установки инструментов

set -e

echo "╔════════════════════════════════════════════════════════╗"
echo "║   🛠️  Установка Code Review Tools                     ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Проверка macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "⚠️  Этот скрипт работает только на macOS"
    exit 1
fi

# Проверка Homebrew
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew не установлен"
    echo ""
    echo "📦 Установите Homebrew:"
    echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

echo "✅ Homebrew найден"
echo ""

# Установка SwiftLint
echo "📦 Установка SwiftLint..."
if command -v swiftlint &> /dev/null; then
    echo "   ✅ SwiftLint уже установлен ($(swiftlint version))"
else
    brew install swiftlint
    echo "   ✅ SwiftLint установлен ($(swiftlint version))"
fi
echo ""

# Установка Periphery (опционально, для поиска мертвого кода)
echo "📦 Установка Periphery (опционально)..."
if command -v periphery &> /dev/null; then
    echo "   ✅ Periphery уже установлен ($(periphery version))"
else
    echo "   ⏳ Устанавливаю Periphery..."
    brew install peripheryapp/periphery/periphery
    echo "   ✅ Periphery установлен ($(periphery version))"
fi
echo ""

# Клонирование Code Review Tools
echo "📥 Клонирование Code Review Tools..."
TOOLS_DIR="$HOME/.swift-code-review-tools"

if [ -d "$TOOLS_DIR" ]; then
    echo "   📂 Директория уже существует, обновляю..."
    cd "$TOOLS_DIR"
    git pull
else
    git clone https://github.com/YOUR_ORG/SwiftCodeReviewTools.git "$TOOLS_DIR"
fi
echo ""

# Сборка инструментов
echo "🔨 Сборка Code Review Tools..."
cd "$TOOLS_DIR"
swift build -c release
echo "   ✅ Инструменты собраны"
echo ""

# Создание символических ссылок
echo "🔗 Создание символических ссылок..."
RELEASE_DIR="$TOOLS_DIR/.build/release"

sudo ln -sf "$RELEASE_DIR/swift-style-check" /usr/local/bin/swift-style-check
sudo ln -sf "$RELEASE_DIR/swift-dead-code" /usr/local/bin/swift-dead-code
sudo ln -sf "$RELEASE_DIR/swift-memory-check" /usr/local/bin/swift-memory-check

echo "   ✅ Ссылки созданы в /usr/local/bin"
echo ""

# Проверка установки
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Установка завершена!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Доступные команды:"
echo "   • swift-style-check <path>    - Проверка стиля кода"
echo "   • swift-dead-code <project>   - Поиск мертвого кода"
echo "   • swift-memory-check <path>   - Проверка утечек памяти"
echo ""
echo "💡 Примеры использования:"
echo "   swift-style-check ."
echo "   swift-dead-code MyProject.xcodeproj"
echo "   swift-memory-check . --static-analysis"
echo ""
