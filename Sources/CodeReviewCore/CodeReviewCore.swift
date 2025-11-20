import Foundation


public struct FileIssue: Codable {
    public let file: String
    public let line: Int?
    public let column: Int?
    public let severity: Severity
    public let rule: String
    public let message: String
    
    public enum Severity: String, Codable {
        case error
        case warning
        case info
    }
    
    public init(file: String, line: Int?, column: Int?, severity: Severity, rule: String, message: String) {
        self.file = file
        self.line = line
        self.column = column
        self.severity = severity
        self.rule = rule
        self.message = message
    }
}

public struct ReviewResult: Codable {
    public let toolName: String
    public let executionTime: Double
    public let filesChecked: Int
    public let issues: [FileIssue]
    public let summary: Summary
    
    public struct Summary: Codable {
        public let errors: Int
        public let warnings: Int
        public let infos: Int
        
        public init(errors: Int, warnings: Int, infos: Int) {
            self.errors = errors
            self.warnings = warnings
            self.infos = infos
        }
    }
    
    public init(toolName: String, executionTime: Double, filesChecked: Int, issues: [FileIssue]) {
        self.toolName = toolName
        self.executionTime = executionTime
        self.filesChecked = filesChecked
        self.issues = issues
        
        let errors = issues.filter { $0.severity == .error }.count
        let warnings = issues.filter { $0.severity == .warning }.count
        let infos = issues.filter { $0.severity == .info }.count
        
        self.summary = Summary(errors: errors, warnings: warnings, infos: infos)
    }
}


public enum OutputFormat {
    case text
    case json
    case html
}

public struct OutputFormatter {
    public static func format(_ result: ReviewResult, as format: OutputFormat) -> String {
        switch format {
        case .text: return formatAsText(result)
        case .json: return formatAsJSON(result)
        case .html: return formatAsHTML(result)
        }
    }
    
    private static func formatAsText(_ result: ReviewResult) -> String {
        var output = """
        ╔════════════════════════════════════════════════════════╗
        ║  \(result.toolName.padding(toLength: 54, withPad: " ", startingAt: 0))  ║
        ╚════════════════════════════════════════════════════════╝
        
        📊 Статистика:
          • Проверено файлов: \(result.filesChecked)
          • Время выполнения: \(String(format: "%.2f", result.executionTime))s
          • ❌ Ошибок: \(result.summary.errors)
          • ⚠️  Предупреждений: \(result.summary.warnings)
          • ℹ️  Информационных: \(result.summary.infos)
        
        """
        
        if result.issues.isEmpty {
            output += "✅ Проблем не обнаружено!\n"
        } else {
            output += "🔍 Найденные проблемы:\n\n"
            for issue in result.issues {
                let icon = issue.severity == .error ? "❌" : (issue.severity == .warning ? "⚠️" : "ℹ️")
                let location = issue.line != nil ? ":\(issue.line!)" : ""
                output += "\(icon) \(issue.file)\(location)\n   [\(issue.rule)] \(issue.message)\n\n"
            }
        }
        
        return output
    }
    
    private static func formatAsJSON(_ result: ReviewResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(result),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"Failed to encode\"}"
        }
        return json
    }
    
    private static func formatAsHTML(_ result: ReviewResult) -> String {
        return "<html><body><h1>\(result.toolName)</h1></body></html>"
    }
}


public struct FileScanner {
    private static var debugMode = false
    
    public static func enableDebug() {
        debugMode = true
    }
    
    public static func findSwiftFiles(in path: String) throws -> [String] {
        let fileManager = FileManager.default
        
        if debugMode {
            print("🛠️ FileScanner: Проверяю путь: \(path)")
        }
        
        // Проверяем существование
        guard fileManager.fileExists(atPath: path) else {
            if debugMode {
                print("🛠️ FileScanner: ❌ Путь не существует!")
            }
            throw NSError(domain: "FileScanner", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Путь не существует: \(path)"
            ])
        }
        
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        
        if debugMode {
            print("🛠️ FileScanner: Это директория? \(isDirectory.boolValue)")
        }
        
        // Если это файл
        if !isDirectory.boolValue {
            if path.hasSuffix(".swift") {
                if debugMode {
                    print("🛠️ FileScanner: ✅ Найден Swift файл: \(path)")
                }
                return [path]
            } else {
                if debugMode {
                    print("🛠️ FileScanner: ⚠️ Это не Swift файл")
                }
                return []
            }
        }
        
        // Если это директория
        if debugMode {
            print("🛠️ FileScanner: Сканирую директорию...")
        }
        
        let url = URL(fileURLWithPath: path)
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw NSError(domain: "FileScanner", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Cannot create enumerator"
            ])
        }
        
        var swiftFiles: [String] = []
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "swift" {
                swiftFiles.append(fileURL.path)
                if debugMode && swiftFiles.count <= 5 {
                    print("🛠️ FileScanner: Найден: \(fileURL.lastPathComponent)")
                }
            }
        }
        
        if debugMode {
            print("🛠️ FileScanner: Всего найдено: \(swiftFiles.count) файлов")
        }
        
        return swiftFiles
    }
}


public struct Shell {
    public struct CommandResult {
        public let stdout: String
        public let stderr: String
        public let exitCode: Int32
        public var output: String { stdout + stderr }
    }
    
    @discardableResult
    public static func run(_ command: String, at path: String? = nil) throws -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        
        if let path = path {
            process.currentDirectoryURL = URL(fileURLWithPath: path)
        }
        
        var outputData = Data()
        var errorData = Data()
        
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        
        outputHandle.readabilityHandler = { handle in
            outputData.append(handle.availableData)
        }
        
        errorHandle.readabilityHandler = { handle in
            errorData.append(handle.availableData)
        }
        
        try process.run()
        process.waitUntilExit()
        
        outputHandle.readabilityHandler = nil
        errorHandle.readabilityHandler = nil
        
        outputData.append(outputHandle.readDataToEndOfFile())
        errorData.append(errorHandle.readDataToEndOfFile())
        
        return CommandResult(
            stdout: String(data: outputData, encoding: .utf8) ?? "",
            stderr: String(data: errorData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}

