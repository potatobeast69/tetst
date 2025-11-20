import Foundation
import ArgumentParser
import CodeReviewCore

@main
struct SwiftDeadCode: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-dead-code",
        abstract: "🗑️ Поиск неиспользуемого кода через Periphery",
        version: "1.1.0"
    )
    
    @Argument(help: "Путь к проекту (.xcodeproj или .xcworkspace)")
    var path: String
    
    @Option(name: .shortAndLong, help: "Формат вывода: text, json, html")
    var format: String = "text"
    
    @Flag(name: .long, help: "Подробный вывод для отладки")
    var verbose: Bool = false
    
    @Option(name: .long, help: "Targets для сканирования (через запятую)")
    var targets: String?
    
    @Option(name: .long, help: "Схема для анализа (если не указана - автодетект)")
    var scheme: String?
    
    @Option(name: .shortAndLong, help: "Сохранить отчет в файл (если не указан - автоматически)")
    var output: String?
    
    @Flag(name: .long, help: "Не сохранять отчет в файл, только консоль")
    var noSave: Bool = false
    
    func run() throws {
        let startTime = Date()
        
        print("🗑️ Поиск неиспользуемого кода...")
        
        // Нормализуем путь к абсолютному
        let absolutePath = resolveAbsolutePath(path)
        print("📁 Путь: \(absolutePath)")
        
        // Находим Periphery (bundled или системный)
        let peripheryPath = findPeripheryPath()
        
        guard let periphery = peripheryPath else {
            print("")
            print("❌ Periphery не найден!")
            print("")
            print("📦 Установите локально:")
            print("   ./setup.sh")
            print("")
            print("📦 Или установите глобально:")
            print("   brew install peripheryapp/periphery/periphery")
            print("")
            print("💡 Или используйте альтернативный подход:")
            print("   swift-memory-check \(absolutePath) --static-analysis")
            throw ExitCode.failure
        }
        
        print("🛠️  Periphery: \(periphery)")
        let version = try getPeripheryVersion(at: periphery)
        print("   Версия: \(version)\n")
        
        // Проверяем что путь это .xcodeproj или .xcworkspace
        guard absolutePath.hasSuffix(".xcodeproj") || absolutePath.hasSuffix(".xcworkspace") else {
            print("⚠️  Periphery требует .xcodeproj или .xcworkspace")
            print("   Укажите: swift-dead-code /path/to/YourProject.xcodeproj")
            throw ExitCode.failure
        }
        
        // Пытаемся автоматически найти схему если не указана
        let schemeToUse: String
        if let explicitScheme = scheme {
            schemeToUse = explicitScheme
            print("📋 Используется схема: \(schemeToUse)")
        } else {
            print("🔍 Автопоиск схемы...")
            if let detectedScheme = try? detectScheme(for: absolutePath) {
                schemeToUse = detectedScheme
                print("✅ Найдена схема: \(schemeToUse)")
            } else {
                print("❌ Не удалось определить схему автоматически")
                print("💡 Укажите схему явно: --scheme YourSchemeName")
                print("")
                print("Доступные схемы:")
                try? listAvailableSchemes(for: absolutePath)
                throw ExitCode.failure
            }
        }
        print("")
        
        // Запускаем Periphery
        print("⏳ Запускаю Periphery (это может занять несколько минут)...\n")
        
        let issues = try runPeriphery(
            peripheryPath: periphery,
            projectPath: absolutePath,
            scheme: schemeToUse
        )
        
        let executionTime = Date().timeIntervalSince(startTime)
        let filesChecked = countSwiftFiles(in: absolutePath)
        
        // Формируем результат
        let result = ReviewResult(
            toolName: "Swift Dead Code (Periphery)",
            executionTime: executionTime,
            filesChecked: filesChecked,
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
        let shouldSaveToFile = !noSave || issues.count > 20
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
                outputPath = "\(reportsDir)/dead-code-report-\(timestamp).\(ext)"
            }
            
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
            
            if format == "json" {
                print("💡 Примеры работы с JSON:")
                print("   cat \(outputPath!) | jq '.issues[] | select(.rule | contains(\"class\"))'")
                print("")
            }
            
        } else {
            outputPath = nil
            let output = OutputFormatter.format(result, as: outputFormat)
            print(output)
        }
        
        if !issues.isEmpty {
            printDeadCodeStatistics(issues)
        }
  
        // Exit code 0 = успешное выполнение анализа (даже если найдены проблемы)
        // Exit code 1 = только при фатальных ошибках (Periphery не найден и т.д.)
        
//        if result.summary.warnings > 0 {
//            throw ExitCode(1)
//        }
    }
    
    // MARK: - Periphery Path Detection
    
    /// Находит путь к Periphery (bundled или системный)
    private func findPeripheryPath() -> String? {
        // 1. Проверяем bundled версию в bin/
        let bundledPaths = [
            "\(#filePath)/../../../../bin/periphery",           // При разработке
            "./bin/periphery",                                   // Относительно CWD
            "\(FileManager.default.currentDirectoryPath)/bin/periphery",
        ]
        
        for bundledPath in bundledPaths {
            let normalizedPath = URL(fileURLWithPath: bundledPath).standardized.path
            if FileManager.default.isExecutableFile(atPath: normalizedPath) {
                return normalizedPath
            }
        }
        
        // 2. Проверяем системную установку
        if let systemPath = try? Shell.run("which periphery"), systemPath.exitCode == 0 {
            let path = systemPath.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return path
            }
        }
        
        return nil
    }
    
    // MARK: - Path Resolution
    
    private func resolveAbsolutePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        
        let fileManager = FileManager.default
        let currentDirectory = fileManager.currentDirectoryPath
        let fullPath = (currentDirectory as NSString).appendingPathComponent(path)
        let url = URL(fileURLWithPath: fullPath)
        return url.standardized.path
    }
    
    // MARK: - Scheme Detection
    
    private func detectScheme(for projectPath: String) throws -> String? {
        let schemes = try getAvailableSchemes(for: projectPath)
        
        if schemes.isEmpty {
            return nil
        }
        
        if schemes.count == 1 {
            return schemes.first
        }
        
        // Пытаемся угадать по имени проекта
        let projectName = URL(fileURLWithPath: projectPath)
            .deletingPathExtension()
            .lastPathComponent
        
        if let match = schemes.first(where: { $0.lowercased() == projectName.lowercased() }) {
            return match
        }
        
        return schemes.first
    }
    
    private func getAvailableSchemes(for projectPath: String) throws -> [String] {
        let projectDir = (projectPath as NSString).deletingLastPathComponent
        
        var command: String
        if projectPath.hasSuffix(".xcworkspace") {
            command = "xcodebuild -workspace \"\(projectPath)\" -list"
        } else {
            command = "xcodebuild -project \"\(projectPath)\" -list"
        }
        
        let result = try Shell.run(command, at: projectDir)
        
        guard result.exitCode == 0 else {
            return []
        }
        
        var schemes: [String] = []
        var inSchemesSection = false
        
        for line in result.stdout.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed == "Schemes:" {
                inSchemesSection = true
                continue
            }
            
            if inSchemesSection {
                if trimmed.isEmpty || trimmed.contains(":") {
                    break
                }
                schemes.append(trimmed)
            }
        }
        
        return schemes
    }
    
    private func listAvailableSchemes(for projectPath: String) throws {
        let schemes = try getAvailableSchemes(for: projectPath)
        
        if schemes.isEmpty {
            print("   Нет доступных схем")
        } else {
            for scheme in schemes {
                print("   • \(scheme)")
            }
        }
    }
    
    // MARK: - Periphery Integration
    
    private func getPeripheryVersion(at path: String) throws -> String {
        let result = try Shell.run("\(path) version")
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func runPeriphery(
        peripheryPath: String,
        projectPath: String,
        scheme: String
    ) throws -> [FileIssue] {
        let projectDir = (projectPath as NSString).deletingLastPathComponent
        
        var command = "\(peripheryPath) scan --format json --quiet"
        
        if projectPath.hasSuffix(".xcodeproj") {
            command += " --project \"\(projectPath)\""
        } else if projectPath.hasSuffix(".xcworkspace") {
            command += " --project \"\(projectPath)\""
        }
        
        command += " --schemes \"\(scheme)\""
        
        if let targets = targets {
            command += " --targets \"\(targets)\""
        }
        
        if verbose {
            print("🔧 Команда Periphery:")
            print("   \(command)")
            print("📂 Рабочая директория: \(projectDir)\n")
        }
        
        let result = try Shell.run(command, at: projectDir)
        
        guard result.exitCode == 0 || !result.stdout.isEmpty else {
            print("❌ Periphery завершился с ошибкой:")
            print(result.stderr)
            throw ExitCode.failure
        }
        
        if verbose {
            print("📦 Размер вывода: \(result.stdout.count) байт")
            print("📄 Первые 1000 символов:")
            print(String(result.stdout.prefix(1000)))
            print("")
        }
        
        if result.stdout.isEmpty || result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "[]" {
            print("ℹ️  Periphery не нашел неиспользуемый код")
            print("   Это означает:")
            print("   1. В проекте нет мертвого кода ✅")
            print("   2. Все файлы добавлены в targets")
            print("   3. Схема '\(scheme)' правильная\n")
        }
        
        return try parsePeripheryOutput(result.stdout)
    }
    
    private func parsePeripheryOutput(_ jsonString: String) throws -> [FileIssue] {
        guard let data = jsonString.data(using: .utf8) else {
            return []
        }
        
        let decoder = JSONDecoder()
        
        do {
            let peripheryIssues = try decoder.decode([PeripheryIssue].self, from: data)
            
            return peripheryIssues.compactMap { issue in
                guard let location = issue.parseLocation() else {
                    if verbose {
                        print("⚠️  Не удалось распарсить: \(issue.location)")
                    }
                    return nil
                }
                
                let message = createMessage(for: issue)
                let severity = determineSeverity(for: issue)
                
                return FileIssue(
                    file: location.file,
                    line: location.line,
                    column: location.column,
                    severity: severity,
                    rule: "unused_\(issue.kind)",
                    message: message
                )
            }
        } catch {
            if verbose {
                print("⚠️  Ошибка парсинга JSON: \(error)")
            }
            return []
        }
    }
    
    private func createMessage(for issue: PeripheryIssue) -> String {
        let icon = getIcon(for: issue.kind)
        let modifiersText = issue.modifiers?.isEmpty == false
            ? " (\(issue.modifiers!.joined(separator: ", ")))"
            : ""
        
        var message = "\(icon) Неиспользуемый \(translateKind(issue.kind)): '\(issue.name)'\(modifiersText)"
        
        if let hints = issue.hints, !hints.isEmpty {
            let hintsText = hints.joined(separator: ", ")
            message += "\n      💡 \(hintsText)"
        }
        
        return message
    }
    
    private func determineSeverity(for issue: PeripheryIssue) -> FileIssue.Severity {
        if issue.modifiers?.contains("public") == true || issue.modifiers?.contains("open") == true {
            return .info
        }
        return .warning
    }
    
    private func translateKind(_ kind: String) -> String {
        switch kind.lowercased() {
        case "class": return "класс"
        case "struct": return "структура"
        case "enum": return "enum"
        case "protocol": return "протокол"
        case "function": return "функция"
        case "method": return "метод"
        case "property": return "свойство"
        case "parameter": return "параметр"
        case "typealias": return "typealias"
        case "associatedtype": return "associatedtype"
        case "import": return "import"
        case "extension": return "extension"
        default: return kind
        }
    }
    
    private func getIcon(for kind: String) -> String {
        switch kind.lowercased() {
        case "class", "struct", "enum": return "🗂️"
        case "protocol": return "📋"
        case "function", "method": return "⚙️"
        case "property": return "📦"
        case "import": return "📥"
        default: return "🗑️"
        }
    }
    
    private func countSwiftFiles(in projectPath: String) -> Int {
        let projectDir = (projectPath as NSString).deletingLastPathComponent
        return (try? FileScanner.findSwiftFiles(in: projectDir).count) ?? 0
    }
    
    private func printDeadCodeStatistics(_ issues: [FileIssue]) {
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 Статистика по неиспользуемому коду:")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        var kindCounts: [String: Int] = [:]
        for issue in issues {
            let kind = issue.rule.replacingOccurrences(of: "unused_", with: "")
            kindCounts[kind, default: 0] += 1
        }
        
        for (kind, count) in kindCounts.sorted(by: { $0.value > $1.value }) {
            let translated = translateKind(kind)
            let icon = getIcon(for: kind)
            print("   \(icon) \(translated.capitalized): \(count)")
        }
        
        print("\n💡 Рекомендации:")
        print("   1. Удалите неиспользуемый код для улучшения читаемости")
        print("   2. Проверьте public элементы - могут использоваться извне")
        print("   3. Рефакторьте большие unused классы постепенно")
        print("   4. Запускайте проверку регулярно в CI/CD")
    }
}

// MARK: - Periphery Models

struct PeripheryIssue: Codable {
    let kind: String
    let name: String
    let modifiers: [String]?
    let location: String
    let hints: [String]?
    let accessibility: String?
    
    func parseLocation() -> (file: String, line: Int, column: Int)? {
        let components = location.split(separator: ":")
        guard components.count >= 3 else { return nil }
        
        guard let line = Int(components[components.count - 2]),
              let column = Int(components[components.count - 1]) else {
            return nil
        }
        
        let fileComponents = components.dropLast(2)
        let file = fileComponents.joined(separator: ":")
        
        return (file: String(file), line: line, column: column)
    }
}
