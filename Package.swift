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
        
        // Crash Reporting - Sentry
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.0.0"),
        
        // Analytics - TelemetryDeck
        .package(url: "https://github.com/TelemetryDeck/SwiftClient", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "NotchAssistant",
            dependencies: [
                .product(name: "SwiftAnthropic", package: "SwiftAnthropic"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "TelemetryDeck", package: "SwiftClient"),
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
