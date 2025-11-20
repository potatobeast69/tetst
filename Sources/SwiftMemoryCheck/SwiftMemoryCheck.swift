import Foundation
import ArgumentParser
import CodeReviewCore

@main
struct SwiftMemoryCheck: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-memory-check",
        abstract: "💾 Анализ утечек памяти и retain cycles",
        version: "1.0.0"
    )
    
    @Argument(help: "Путь к директории для проверки")
    var path: String
    
    @Option(name: .shortAndLong, help: "Формат вывода: text, json, html")
    var format: String = "text"
    
    @Flag(name: .long, help: "Статический анализ (без запуска приложения)")
    var staticAnalysis: Bool = false
    
    @Flag(name: .long, help: "Интеграция с LifetimeTracker для runtime анализа")
    var runtimeAnalysis: Bool = false
    
    @Option(name: .shortAndLong, help: "Сохранить отчет в файл (если не указан - автоматически)")
    var output: String?
    
    @Flag(name: .long, help: "Не сохранять отчет в файл, только консоль")
    var noSave: Bool = false
    
    func run() throws {
        let startTime = Date()
        
        print("💾 Анализ утечек памяти...")
        print("📁 Путь: \(path)\n")
        
        if !staticAnalysis && !runtimeAnalysis {
            print("⚠️  Выберите хотя бы один режим:")
            print("   --static-analysis - статический анализ кода")
            print("   --runtime-analysis - runtime анализ с LifetimeTracker")
            throw ExitCode.failure
        }
        
        var allIssues: [FileIssue] = []
        
        // 1. Статический анализ
        if staticAnalysis {
            print("🔍 Статический анализ retain cycles...\n")
            let staticIssues = try performStaticAnalysis()
            allIssues.append(contentsOf: staticIssues)
        }
        
        // 2. Runtime анализ через LifetimeTracker
        if runtimeAnalysis {
            print("🔍 Runtime анализ с LifetimeTracker...\n")
            let runtimeIssues = try performRuntimeAnalysis()
            allIssues.append(contentsOf: runtimeIssues)
        }
        
        let executionTime = Date().timeIntervalSince(startTime)
        let filesChecked = (try? FileScanner.findSwiftFiles(in: path).count) ?? 0
        
        let result = ReviewResult(
            toolName: "Swift Memory Check",
            executionTime: executionTime,
            filesChecked: filesChecked,
            issues: allIssues
        )
        
        let outputFormat: OutputFormat = {
            switch format.lowercased() {
            case "json": return .json
            case "html": return .html
            default: return .text
            }
        }()
        
        // Определяем куда сохранять
        let shouldSaveToFile = !noSave || allIssues.count > 50 || filesChecked > 30
        let outputPath: String?
        
        if shouldSaveToFile {
            // Автоматический путь или указанный пользователем
            if let userOutput = output {
                outputPath = userOutput
            } else {
                // Создаем reports директорию
                let reportsDir = FileManager.default.currentDirectoryPath + "/reports"
                try? FileManager.default.createDirectory(
                    atPath: reportsDir,
                    withIntermediateDirectories: true
                )
                
                let timestamp = ISO8601DateFormatter().string(from: Date())
                    .replacingOccurrences(of: ":", with: "-")
                    .replacingOccurrences(of: ".", with: "-")
                let ext = format == "html" ? "html" : format == "json" ? "json" : "txt"
                outputPath = "\(reportsDir)/memory-report-\(timestamp).\(ext)"
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
            
            // Если HTML - предложить открыть
            if format == "html" {
                print("💡 Открыть в браузере:")
                print("   open \(outputPath!)")
                print("")
            }
            
            // Если JSON - показать пример использования
            if format == "json" {
                print("💡 Использование JSON:")
                print("   cat \(outputPath!) | jq '.issues[] | select(.severity==\"error\")'")
                print("")
            }
            
        } else {
            // Выводим в консоль (если файлов мало)
            outputPath = nil
            let output = OutputFormatter.format(result, as: outputFormat)
            print(output)
        }
        
        printMemoryStatistics(allIssues)
  
        // Exit code 0 = успешное выполнение анализа (даже если найдены проблемы)
        // Exit code 1 = только при фатальных ошибках (файл не найден и т.д.)
        
//        if result.summary.errors > 0 || result.summary.warnings > 0 {
//            throw ExitCode(1)
//        }
    }
    
    // MARK: - Статический анализ
    
    private func performStaticAnalysis() throws -> [FileIssue] {
        var issues: [FileIssue] = []
        
        let swiftFiles = try FileScanner.findSwiftFiles(in: path)
        
        for file in swiftFiles {
            let content = try String(contentsOfFile: file, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            
            // 1. Поиск потенциальных retain cycles в closures
            issues.append(contentsOf: checkRetainCycles(
                content: content,
                lines: lines,
                file: file
            ))
            
            // 2. Проверка weak/unowned использования
            issues.append(contentsOf: checkWeakReferences(
                content: content,
                lines: lines,
                file: file
            ))
            
            // 3. Delegate без weak
            issues.append(contentsOf: checkDelegateProperties(
                content: content,
                lines: lines,
                file: file
            ))
            
            // 4. Closure capture lists
            issues.append(contentsOf: checkClosureCaptureList(
                content: content,
                lines: lines,
                file: file
            ))
        }
        
        return issues
    }
    
    private func checkRetainCycles(content: String, lines: [String], file: String) -> [FileIssue] {
        var issues: [FileIssue] = []
        
        // Ищем closures с self без [weak self] или [unowned self]
        for (index, line) in lines.enumerated() {
            // Closure начинается с { и содержит self
            if line.contains("{") && !line.contains("[weak self]") && !line.contains("[unowned self]") {
                // Проверяем следующие несколько строк на использование self
                let nextLines = lines[min(index + 1, lines.count)..<min(index + 10, lines.count)]
                let useSelf = nextLines.contains { $0.contains("self.") || $0.contains("self?.") }
                
                if useSelf {
                    // Проверяем, что это НЕ escaping closure (тогда это OK)
                    let isEscaping = line.contains("@escaping") ||
                                    (index > 0 && lines[index - 1].contains("@escaping"))
                    
                    if isEscaping {
                        issues.append(FileIssue(
                            file: file,
                            line: index + 1,
                            column: nil,
                            severity: .warning,
                            rule: "potential_retain_cycle",
                            message: "⚠️ Потенциальный retain cycle: escaping closure использует self без [weak self]"
                        ))
                    }
                }
            }
        }
        
        return issues
    }
    
    private func checkWeakReferences(content: String, lines: [String], file: String) -> [FileIssue] {
        var issues: [FileIssue] = []
        
        // Ищем использование weak self без проверки
        for (index, line) in lines.enumerated() {
            if line.contains("[weak self]") {
                // Проверяем следующие строки на прямое использование self без guard
                let nextLine = index + 1 < lines.count ? lines[index + 1] : ""
                
                if nextLine.contains("self.") && !nextLine.contains("guard") && !nextLine.contains("self?") {
                    issues.append(FileIssue(
                        file: file,
                        line: index + 2,
                        column: nil,
                        severity: .info,
                        rule: "weak_self_usage",
                        message: "💡 [weak self] использован, но self не проверен через guard. Используйте guard let self = self или self?"
                    ))
                }
            }
        }
        
        return issues
    }
    
    private func checkDelegateProperties(content: String, lines: [String], file: String) -> [FileIssue] {
        var issues: [FileIssue] = []
        
        // Ищем delegate свойства без weak
        for (index, line) in lines.enumerated() {
            if line.contains("delegate") && line.contains("var") {
                let hasWeak = line.contains("weak var")
                let hasUnowned = line.contains("unowned var")
                
                if !hasWeak && !hasUnowned {
                    issues.append(FileIssue(
                        file: file,
                        line: index + 1,
                        column: nil,
                        severity: .warning,
                        rule: "delegate_not_weak",
                        message: "⚠️ Delegate свойство должно быть weak для избежания retain cycle"
                    ))
                }
            }
        }
        
        return issues
    }
    
    private func checkClosureCaptureList(content: String, lines: [String], file: String) -> [FileIssue] {
        var issues: [FileIssue] = []
        
        // Ищем stored closures без capture list
        for (index, line) in lines.enumerated() {
            // Stored closure: var something: () -> Void = { ... }
            if line.contains("var") && line.contains("->") && line.contains("= {") {
                if !line.contains("[") { // нет capture list
                    // Проверяем, используется ли self в closure
                    let closureStart = index
                    var braceCount = 0
                    var foundSelf = false
                    
                    for i in closureStart..<min(closureStart + 20, lines.count) {
                        let l = lines[i]
                        braceCount += l.filter { $0 == "{" }.count
                        braceCount -= l.filter { $0 == "}" }.count
                        
                        if l.contains("self") {
                            foundSelf = true
                        }
                        
                        if braceCount == 0 {
                            break
                        }
                    }
                    
                    if foundSelf {
                        issues.append(FileIssue(
                            file: file,
                            line: index + 1,
                            column: nil,
                            severity: .warning,
                            rule: "stored_closure_retain_cycle",
                            message: "⚠️ Stored closure использует self без capture list. Добавьте [weak self] или [unowned self]"
                        ))
                    }
                }
            }
        }
        
        return issues
    }
    
    // MARK: - Runtime анализ через LifetimeTracker
    
    private func performRuntimeAnalysis() throws -> [FileIssue] {
        print("⚠️  Runtime анализ требует запуска приложения с LifetimeTracker")
        print("📖 Инструкции:")
        print("   1. Добавьте LifetimeTracker в проект:")
        print("      pod 'LifetimeTracker'")
        print("   2. Инициализируйте в AppDelegate:")
        print("      #if DEBUG")
        print("      LifetimeTracker.setup()")
        print("      #endif")
        print("   3. Добавьте trackLifetime() в классы")
        print("   4. Запустите приложение и проверьте dashboard\n")
        
        // Проверяем, используется ли LifetimeTracker в коде
        var issues: [FileIssue] = []
        
        let swiftFiles = try FileScanner.findSwiftFiles(in: path)
        var hasLifetimeTracker = false
        
        for file in swiftFiles {
            let content = try String(contentsOfFile: file, encoding: .utf8)
            if content.contains("import LifetimeTracker") {
                hasLifetimeTracker = true
                break
            }
        }
        
        if !hasLifetimeTracker {
            issues.append(FileIssue(
                file: path,
                line: nil,
                column: nil,
                severity: .info,
                rule: "lifetime_tracker_not_found",
                message: "ℹ️ LifetimeTracker не найден в проекте. Добавьте для runtime анализа утечек памяти"
            ))
        }
        
        return issues
    }
    
    // MARK: - Статистика
    
    private func printMemoryStatistics(_ issues: [FileIssue]) {
        guard !issues.isEmpty else { return }
        
        print("\n📊 Статистика по утечкам памяти:")
        
        var categoryCounts: [String: Int] = [:]
        for issue in issues {
            categoryCounts[issue.rule, default: 0] += 1
        }
        
        for (rule, count) in categoryCounts.sorted(by: { $0.value > $1.value }) {
            let name = translateRule(rule)
            print("   • \(name): \(count)")
        }
        
        print("\n💡 Рекомендации:")
        print("   1. Всегда используйте [weak self] в escaping closures")
        print("   2. Delegate свойства должны быть weak")
        print("   3. Используйте LifetimeTracker для runtime мониторинга")
        print("   4. Проверяйте Instruments → Leaks регулярно")
    }
    
    private func translateRule(_ rule: String) -> String {
        switch rule {
        case "potential_retain_cycle": return "Потенциальные retain cycles"
        case "weak_self_usage": return "Использование weak self"
        case "delegate_not_weak": return "Delegate без weak"
        case "stored_closure_retain_cycle": return "Stored closures с retain cycle"
        case "lifetime_tracker_not_found": return "LifetimeTracker не найден"
        default: return rule
        }
    }
}
