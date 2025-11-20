#!/bin/bash

set -e

echo "🔧 Настройка SwiftCodeReviewTools..."
echo ""

# Определяем директорию проекта
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$PROJECT_DIR/bin"

# Создаем директорию для бинарников
mkdir -p "$BIN_DIR"

echo "📁 Директория для бинарников: $BIN_DIR"
echo ""

# Определяем платформу
OS="$(uname -s)"
ARCH="$(uname -m)"

echo "💻 Платформа: $OS $ARCH"
echo ""

# Проверяем что это macOS
if [ "$OS" != "Darwin" ]; then
    echo "❌ Этот скрипт работает только на macOS"
    echo "   Ваша ОС: $OS"
    exit 1
fi

# Версии инструментов
SWIFTLINT_VERSION="0.62.2"
PERIPHERY_VERSION="2.20.0"

# Функция для установки SwiftLint
install_swiftlint() {
    echo "📦 Установка SwiftLint $SWIFTLINT_VERSION..."
    
    SWIFTLINT_URL="https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip"
    
    echo "   Скачивание: $SWIFTLINT_URL"
    if ! curl -L -f -o "$BIN_DIR/swiftlint.zip" "$SWIFTLINT_URL"; then
        echo "   ❌ Ошибка скачивания SwiftLint"
        rm -f "$BIN_DIR/swiftlint.zip"
        return 1
    fi
    
    echo "   Распаковка..."
    if ! unzip -q "$BIN_DIR/swiftlint.zip" -d "$BIN_DIR"; then
        echo "   ❌ Ошибка распаковки SwiftLint"
        rm -f "$BIN_DIR/swiftlint.zip"
        return 1
    fi
    
    rm -f "$BIN_DIR/swiftlint.zip"
    chmod +x "$BIN_DIR/swiftlint"
    
    echo "   ✅ SwiftLint установлен: $BIN_DIR/swiftlint"
    echo ""
    return 0
}

# Функция для установки Periphery через Homebrew API
install_periphery() {
    echo "📦 Установка Periphery $PERIPHERY_VERSION..."
    
    # Получаем информацию о релизе через GitHub API
    echo "   Получение ссылки на скачивание..."
    
    RELEASE_INFO=$(curl -s "https://api.github.com/repos/peripheryapp/periphery/releases/tags/${PERIPHERY_VERSION}")
    
    # Ищем правильный asset для macOS
    PERIPHERY_URL=$(echo "$RELEASE_INFO" | grep "browser_download_url" | grep "macos.zip" | head -n 1 | cut -d '"' -f 4)
    
    if [ -z "$PERIPHERY_URL" ]; then
        echo "   ⚠️  Не удалось найти ссылку для скачивания"
        echo ""
        echo "   🔧 Установите Periphery вручную:"
        echo "   1. Через Homebrew:"
        echo "      brew install peripheryapp/periphery/periphery"
        echo ""
        echo "   2. Или скачайте вручную:"
        echo "      https://github.com/peripheryapp/periphery/releases/tag/${PERIPHERY_VERSION}"
        echo "      Распакуйте в: $BIN_DIR/"
        echo ""
        return 1
    fi
    
    echo "   Скачивание: $PERIPHERY_URL"
    if ! curl -L -f -o "$BIN_DIR/periphery.zip" "$PERIPHERY_URL"; then
        echo "   ❌ Ошибка скачивания Periphery"
        rm -f "$BIN_DIR/periphery.zip"
        return 1
    fi
    
    # Проверяем размер файла (должен быть больше 1 MB)
    FILE_SIZE=$(stat -f%z "$BIN_DIR/periphery.zip" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -lt 1000000 ]; then
        echo "   ❌ Скачанный файл слишком маленький ($FILE_SIZE байт)"
        rm -f "$BIN_DIR/periphery.zip"
        return 1
    fi
    
    echo "   Распаковка..."
    if ! unzip -q "$BIN_DIR/periphery.zip" -d "$BIN_DIR/periphery_temp"; then
        echo "   ❌ Ошибка распаковки Periphery"
        rm -f "$BIN_DIR/periphery.zip"
        rm -rf "$BIN_DIR/periphery_temp"
        return 1
    fi
    
    # Ищем бинарник periphery в распакованной структуре
    PERIPHERY_BIN=$(find "$BIN_DIR/periphery_temp" -name "periphery" -type f | head -n 1)
    
    if [ -z "$PERIPHERY_BIN" ]; then
        echo "   ❌ Не найден бинарник periphery в архиве"
        rm -f "$BIN_DIR/periphery.zip"
        rm -rf "$BIN_DIR/periphery_temp"
        return 1
    fi
    
    # Перемещаем бинарник
    mv "$PERIPHERY_BIN" "$BIN_DIR/periphery"
    
    # Очищаем
    rm -f "$BIN_DIR/periphery.zip"
    rm -rf "$BIN_DIR/periphery_temp"
    
    chmod +x "$BIN_DIR/periphery"
    
    echo "   ✅ Periphery установлен: $BIN_DIR/periphery"
    echo ""
    return 0
}

# Проверяем, установлен ли уже SwiftLint
if [ -f "$BIN_DIR/swiftlint" ]; then
    echo "✅ SwiftLint уже установлен в $BIN_DIR/swiftlint"
    CURRENT_VERSION=$("$BIN_DIR/swiftlint" version 2>/dev/null || echo "unknown")
    echo "   Версия: $CURRENT_VERSION"
    echo ""
else
    if ! install_swiftlint; then
        echo "⚠️  SwiftLint не установлен"
    fi
fi

# Проверяем, установлен ли уже Periphery
if [ -f "$BIN_DIR/periphery" ]; then
    echo "✅ Periphery уже установлен в $BIN_DIR/periphery"
    CURRENT_VERSION=$("$BIN_DIR/periphery" version 2>/dev/null || echo "unknown")
    echo "   Версия: $CURRENT_VERSION"
    echo ""
else
    if ! install_periphery; then
        echo "⚠️  Periphery не установлен"
        echo ""
        echo "💡 Быстрая установка через Homebrew:"
        echo "   brew install peripheryapp/periphery/periphery"
        echo ""
        echo "   CLI инструменты будут использовать системную версию"
        echo ""
    fi
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Настройка завершена!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Итоговая статистика
echo "📊 Установленные инструменты:"
SWIFTLINT_OK=false
PERIPHERY_OK=false

if [ -f "$BIN_DIR/swiftlint" ]; then
    SWIFTLINT_VER=$("$BIN_DIR/swiftlint" version 2>/dev/null || echo "unknown")
    echo "   ✅ SwiftLint: $SWIFTLINT_VER ($BIN_DIR/swiftlint)"
    SWIFTLINT_OK=true
else
    echo "   ❌ SwiftLint: не установлен"
fi

if [ -f "$BIN_DIR/periphery" ]; then
    PERIPHERY_VER=$("$BIN_DIR/periphery" version 2>/dev/null || echo "unknown")
    echo "   ✅ Periphery: $PERIPHERY_VER ($BIN_DIR/periphery)"
    PERIPHERY_OK=true
else
    echo "   ⚠️  Periphery: не установлен (используйте brew или ручную установку)"
fi

echo ""
echo "📦 Размер bin/:"
du -sh "$BIN_DIR" 2>/dev/null || echo "   Неизвестно"
echo ""

echo "🚀 Следующие шаги:"
echo ""
echo "   1. Соберите проект:"
echo "      swift build -c release"
echo ""
echo "   2. Используйте инструменты:"

if [ "$SWIFTLINT_OK" = true ]; then
    echo "      .build/release/swift-style-check /path/to/project"
fi

if [ "$PERIPHERY_OK" = true ]; then
    echo "      .build/release/swift-dead-code /path/to/project.xcodeproj --scheme YourScheme"
fi

echo "      .build/release/swift-memory-check /path/to/project --static-analysis"
echo ""

if [ "$PERIPHERY_OK" = false ]; then
    echo "💡 Для установки Periphery:"
    echo "   brew install peripheryapp/periphery/periphery"
    echo ""
fi

echo "✨ Готово! Все bundled зависимости в папке bin/"
echo ""
