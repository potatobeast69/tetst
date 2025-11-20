// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftCodeReviewTools",
    platforms: [
        .macOS(.v13)
    ],
    products: [

        .executable(
            name: "swift-style-check",
            targets: ["SwiftStyleCheck"]
        ),
        
        .executable(
            name: "swift-dead-code",
            targets: ["SwiftDeadCode"]
        ),
                
        .executable(
            name: "swift-memory-check",
            targets: ["SwiftMemoryCheck"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-syntax", from: "509.0.0"),
    ],
    targets: [
        .target(
            name: "CodeReviewCore",
            dependencies: []
        ),
        
        .executableTarget(
            name: "SwiftStyleCheck",
            dependencies: [
                "CodeReviewCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        
        .executableTarget(
            name: "SwiftDeadCode",
            dependencies: [
                "CodeReviewCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
                
        .executableTarget(
            name: "SwiftMemoryCheck",
            dependencies: [
                "CodeReviewCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
