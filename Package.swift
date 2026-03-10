// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchAssistant",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchAssistant", targets: ["NotchAssistant"])
    ],
    dependencies: [
        // LLM - Anthropic Claude API
        .package(url: "https://github.com/jamesrochabrun/SwiftAnthropic", from: "2.1.0"),
        
        // Speech-to-Text - WhisperKit
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        
        // Notch UI - DynamicNotchKit
        .package(url: "https://github.com/MrKai77/DynamicNotchKit", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "NotchAssistant",
            dependencies: [
                .product(name: "SwiftAnthropic", package: "SwiftAnthropic"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit"),
            ],
            path: "NotchAssistant/NotchAssistant",
            exclude: ["Info.plist", "NotchAssistant.entitlements"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "NotchAssistantTests",
            dependencies: ["NotchAssistant"],
            path: "NotchAssistantTests"
        ),
    ]
)
