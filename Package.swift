// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AbyssLTranslator",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "AbyssLTranslator", targets: ["AbyssLTranslator"]),
    ],
    targets: [
        .executableTarget(
            name: "AbyssLTranslator",
            dependencies: [],
            path: "Sources/AbyssLTranslator",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
