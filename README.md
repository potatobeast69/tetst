# 🛠️ SwiftCodeReviewTools

Swift code review automation tools for iOS/macOS projects.

## 🎯 Tools

- **swift-style-check**: Code style checking with SwiftLint
- **swift-dead-code**: Find unused code with Periphery (macOS only)
- **swift-memory-check**: Memory leak and retain cycle detection

## 📦 Installation

### macOS
Download the latest release from [Releases](https://github.com/YOUR_USERNAME/SwiftCodeReviewTools/releases)
```bash
# Extract
tar -xzf swiftcodereview-macos.tar.gz

# Run
./macos/swift-style-check /path/to/project
```

### Linux
```bash
# Extract
tar -xzf swiftcodereview-linux.tar.gz

# Run (swift-dead-code not available on Linux)
./linux/swift-style-check /path/to/project
./linux/swift-memory-check /path/to/project --static-analysis
```

## 🔨 Build from source

### Setup bundled dependencies (macOS only)
```bash
./setup.sh
```

### Build
```bash
swift build -c release
```

### Run
```bash
.build/release/swift-style-check /path/to/project
.build/release/swift-dead-code /path/to/project.xcodeproj --scheme YourScheme
.build/release/swift-memory-check /path/to/project --static-analysis
```

## 📖 Usage Examples

### swift-style-check
```bash
# Basic check
swift-style-check /path/to/project

# JSON output
swift-style-check /path/to/project --format json

# Strict mode (warnings = errors)
swift-style-check /path/to/project --strict

# Auto-fix issues
swift-style-check /path/to/project --fix
```

### swift-dead-code (macOS only)
```bash
# Scan project
swift-dead-code /path/to/project.xcodeproj --scheme YourScheme

# JSON output
swift-dead-code /path/to/project.xcodeproj --scheme YourScheme --format json

# Specify targets
swift-dead-code /path/to/project.xcodeproj --scheme YourScheme --targets "App,Framework"
```

### swift-memory-check
```bash
# Static analysis
swift-memory-check /path/to/project --static-analysis

# Runtime analysis recommendations
swift-memory-check /path/to/project --runtime-analysis

# JSON output
swift-memory-check /path/to/project --static-analysis --format json
```

## 🤖 CI/CD Integration

All tools return exit code 0 on successful analysis (even if issues found).
Use `--strict` flag for swift-style-check to fail on warnings.

### GitHub Actions Example
```yaml
- name: Run Swift Style Check
  run: |
    swift-style-check . --format json --output style-report.json
    
- name: Run Memory Check
  run: |
    swift-memory-check . --static-analysis --format json --output memory-report.json
```

## 📝 License

MIT
