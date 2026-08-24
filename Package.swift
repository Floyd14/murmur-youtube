// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WisperClone",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "WisperDictionary",
            path: "Sources/WisperDictionary",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "WisperFormatting",
            path: "Sources/WisperFormatting",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "WisperClone",
            dependencies: ["WisperDictionary", "WisperFormatting"],
            path: "Sources/WisperClone",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "WisperDictionaryTests",
            dependencies: ["WisperDictionary"],
            path: "Tests/WisperDictionaryTests",
            resources: [.copy("dictionary-test-vectors.json")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "WisperFormattingTests",
            dependencies: ["WisperFormatting"],
            path: "Tests/WisperFormattingTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
