import Foundation
import ArgumentParser
import CodeReviewCore

@main
struct SwiftStyleCheck: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-style-check",
        abstract: "🎨 Проверка единообразия стиля кода с помощью SwiftLint",
        version: "2.0.0"
    )
    
    @Argument(help: "Путь к директории или файлу для проверки")
    var path: String
    
    @Option(name: .shortAndLong, help: "Формат вывода: text, json, html")
    var format: String = "text"
    
    @Flag(name: .long, help: "Строгий режим (предупреждения = ошибки)")
    var strict: Bool = false
    
    @Option(
        name: [.customLong("config"), .customLong("rules-path")],
        help: "Путь к конфигурации SwiftLint (.swiftlint.yml)"
    )
    var config: String?
    
    @Option(
        name: [.customLong("swiftlint-path"), .customLong("swift-lint-path")],
        help: "Путь к бинарнику SwiftLint (если не указан - автопоиск)"
    )
    var swiftlintPath: String?
    
    @Flag(name: .long, help: "Автоматически исправить проблемы (где возможно)")
    var fix: Bool = false
    
    @Option(name: .shortAndLong, help: "Сохранить отчет в файл (если не указан - автоматически)")
    var output: String?
    
    @Flag(name: .long, help: "Не сохранять отчет в файл, только консоль")
    var noSave: Bool = false
    
    @Flag(name: .long, help: "Подробный вывод для отладки")
    var verbose: Bool = false
    
    func run() throws {
        let startTime = Date()

        print("╔════════════════════════════════════════════════════════╗")
        print("║          🎨 SWIFT STYLE CHECK v2.0.0                   ║")
        print("╚════════════════════════════════════════════════════════╝")
        print("")

        // Находим SwiftLint
        let resolvedSwiftLintPath = try resolveSwiftLintPath()

        print("🔍 Начинаю проверку стиля кода...")
        print("📁 Путь: \(path)")
        print("🛠️  SwiftLint: \(resolvedSwiftLintPath)")

        if let version = getSwiftLintVersion(at: resolvedSwiftLintPath) {
            print("   Версия: \(version)")
        }

        if let configPath = config {
            print("📋 Конфигурация: \(configPath)")
        }

        print("")

        // Находим Swift файлы
        let swiftFiles = try FileScanner.findSwiftFiles(in: path)
        let filesCount = swiftFiles.count
        print("✅ Найдено Swift файлов: \(swiftFiles.count)")

        if swiftFiles.count > 50 {
            print("⚠️  Обнаружено много файлов (\(swiftFiles.count))")
            print("   Результаты будут автоматически сохранены в файл\n")
        }

        print("⏳ Запускаю SwiftLint...\n")

        // Запускаем SwiftLint
        let issues = try runSwiftLint(swiftlintPath: resolvedSwiftLintPath, on: path)
        
        let executionTime = Date().timeIntervalSince(startTime)
        
        // Формируем результат (работает в обоих случаях)
        let result = ReviewResult(
            toolName: "Swift Style Check",
            executionTime: executionTime,
            filesChecked: filesCount,
            issues: issues
        )
        
        let outputFormat: OutputFormat = {
            switch format.lowercased() {
            case "json": return .json
            case "html": return .html
            default: return .text
            }
        }()
        
        // Определяем куда сохранять
        let shouldSaveToFile = !noSave || issues.count > 100 || filesCount > 50
        let outputPath: String?
        
        if shouldSaveToFile {
            if let userOutput = output {
                outputPath = userOutput
            } else {
                let reportsDir = FileManager.default.currentDirectoryPath + "/reports"
                try? FileManager.default.createDirectory(
                    atPath: reportsDir,
                    withIntermediateDirectories: true
                )
                
                let timestamp = ISO8601DateFormatter().string(from: Date())
                    .replacingOccurrences(of: ":", with: "-")
                    .replacingOccurrences(of: ".", with: "-")
                let ext = format == "html" ? "html" : format == "json" ? "json" : "txt"
                outputPath = "\(reportsDir)/style-report-\(timestamp).\(ext)"
            }
            
            // Сохраняем в файл
            let fullOutput = OutputFormatter.format(result, as: outputFormat)
            try fullOutput.write(toFile: outputPath!, atomically: true, encoding: .utf8)
            
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📊 Краткая статистика:")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("  • Проверено файлов: \(result.filesChecked)")
            print("  • Время выполнения: \(String(format: "%.2f", result.executionTime))s")
            print("  • ❌ Ошибок: \(result.summary.errors)")
            print("  • ⚠️  Предупреждений: \(result.summary.warnings)")
            print("  • ℹ️  Информационных: \(result.summary.infos)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("")
            print("📄 Полный отчет сохранен:")
            print("   \(outputPath!)")
            print("")
            
            if format == "html" {
                print("💡 Открыть в браузере:")
                print("   open \(outputPath!)")
                print("")
            }
            
        } else {
            outputPath = nil
            let output = OutputFormatter.format(result, as: outputFormat)
            print(output)
        }

        // Strict режим
        if strict && result.summary.warnings > 0 {
            throw ExitCode(1)
        }
    }
    
    // MARK: - SwiftLint Path Resolution
    
    /// Находит и проверяет путь к SwiftLint
    private func resolveSwiftLintPath() throws -> String {
        // 1. Если путь явно указан пользователем - используем его
        if let explicitPath = swiftlintPath {
            let normalizedPath = URL(fileURLWithPath: explicitPath).standardized.path
            
            // Проверяем что файл существует и исполняемый
            guard FileManager.default.fileExists(atPath: normalizedPath) else {
                print("❌ SwiftLint не найден по указанному пути:")
                print("   \(normalizedPath)")
                throw ExitCode.failure
            }
            
            guard FileManager.default.isExecutableFile(atPath: normalizedPath) else {
                print("❌ Файл найден, но не является исполняемым:")
                print("   \(normalizedPath)")
                print("")
                print("💡 Попробуйте:")
                print("   chmod +x \(normalizedPath)")
                throw ExitCode.failure
            }
            
            return normalizedPath
        }
        
        // 2. Автопоиск: bundled или системный
        if let foundPath = findSwiftLintPath() {
            return foundPath
        }
        
        // 3. Не найден нигде
        print("❌ SwiftLint не найден!")
        print("")
        print("📦 Варианты установки:")
        print("")
        print("1. Локально (bundled):")
        print("   ./setup.sh")
        print("")
        print("2. Глобально через Homebrew:")
        print("   brew install swiftlint")
        print("")
        print("3. Укажите путь явно:")
        print("   swift-style-check /path --swiftlint-path /custom/path/to/swiftlint")
        print("")
        throw ExitCode.failure
    }
    
    /// Находит путь к SwiftLint (bundled или системный)
    private func findSwiftLintPath() -> String? {
        // 1. Проверяем bundled версию в bin/
        let bundledPaths = [
            "\(#filePath)/../../../../bin/swiftlint",           // При разработке
            "./bin/swiftlint",                                   // Относительно CWD
            "\(FileManager.default.currentDirectoryPath)/bin/swiftlint",
        ]
        
        for bundledPath in bundledPaths {
            let normalizedPath = URL(fileURLWithPath: bundledPath).standardized.path
            if FileManager.default.isExecutableFile(atPath: normalizedPath) {
                return normalizedPath
            }
        }
        
        // 2. Проверяем системную установку
        if let systemPath = try? Shell.run("which swiftlint"), systemPath.exitCode == 0 {
            let path = systemPath.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return path
            }
        }
        
        return nil
    }
    
    private func getSwiftLintVersion(at path: String) -> String? {
        guard let result = try? Shell.run("\(path) version"),
              result.exitCode == 0 else {
            return nil
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func runSwiftLint(swiftlintPath: String, on path: String) throws -> [FileIssue] {
        var command = "\(swiftlintPath) lint --reporter json"
        
        if let config = config {
            // Проверяем что файл конфигурации существует
            let configPath = URL(fileURLWithPath: config).standardized.path
            if FileManager.default.fileExists(atPath: configPath) {
                command += " --config \"\(config)\""
            } else {
                print("⚠️  Файл конфигурации не найден:")
                print("   \(configPath)")
                print("")
                print("💡 Продолжаю без конфигурации...")
                print("")
            }
        }
        
        if fix {
            print("🔧 Применяю автоматические исправления...")
            var fixCommand = "\(swiftlintPath) --fix"
            if let config = config {
                fixCommand += " --config \"\(config)\""
            }
            _ = try? Shell.run(fixCommand, at: path)
            print("✅ Исправления применены\n")
        }
        
        // Добавляем индикатор для длительных операций
        print("⏳ SwiftLint анализирует код...")
        print("   (это может занять некоторое время для больших проектов)")
        
        let startTime = Date()
        let result = try Shell.run(command, at: path)
        let duration = Date().timeIntervalSince(startTime)
        
        print("✅ SwiftLint завершил работу за \(String(format: "%.1f", duration))s")
        
        // Используем ТОЛЬКО stdout для JSON (игнорируем stderr с информационными сообщениями)
        let jsonOutput = result.stdout
        print("📦 Размер вывода: \(ByteCountFormatter.string(fromByteCount: Int64(jsonOutput.count), countStyle: .file))")
        
        // Показываем stderr если есть (обычно там warnings о конфигурации)
        if !result.stderr.isEmpty && verbose {
            print("ℹ️  SwiftLint stderr: \(result.stderr.prefix(200))...")
        }
        print("")
        
        // Парсим JSON результат от SwiftLint (только stdout!)
        guard let data = jsonOutput.data(using: .utf8), !jsonOutput.isEmpty else {
            print("⚠️  Пустой вывод от SwiftLint")
            return []
        }
        
        struct SwiftLintResult: Codable {
            let file: String
            let line: Int?
            let column: Int?
            let severity: String
            let rule_id: String
            let reason: String
        }
        
        let decoder = JSONDecoder()
        
        // Пытаемся распарсить JSON
        do {
            let swiftLintResults = try decoder.decode([SwiftLintResult].self, from: data)
            print("🔍 Найдено проблем: \(swiftLintResults.count)\n")
            
            return swiftLintResults.map { result in
                FileIssue(
                    file: result.file,
                    line: result.line,
                    column: result.column,
                    severity: result.severity == "error" ? .error : .warning,
                    rule: result.rule_id,
                    message: result.reason
                )
            }
        } catch {
            if verbose {
                print("⚠️  Ошибка парсинга JSON от SwiftLint: \(error)")
                print("   Размер stdout: \(jsonOutput.count) байт")
                print("   Размер stderr: \(result.stderr.count) байт")
                print("   Первые 500 символов stdout:")
                print("   \(jsonOutput.prefix(500))")
            }
            
            // Попытка найти где заканчивается валидный JSON
            if let lastBracket = jsonOutput.lastIndex(of: "]") {
                let validJson = String(jsonOutput[...lastBracket])
                
                if verbose {
                    print("\n   💡 Попытка парсинга очищенного JSON (до последней ']')...")
                }
                
                if let cleanData = validJson.data(using: .utf8),
                   let cleanResults = try? decoder.decode([SwiftLintResult].self, from: cleanData) {
                    print("   ✅ Успешно! Найдено проблем: \(cleanResults.count)\n")
                    
                    return cleanResults.map { result in
                        FileIssue(
                            file: result.file,
                            line: result.line,
                            column: result.column,
                            severity: result.severity == "error" ? .error : .warning,
                            rule: result.rule_id,
                            message: result.reason
                        )
                    }
                }
            }
            
            print("   ❌ Очистка не помогла\n")
            return []
        }
    }
}
