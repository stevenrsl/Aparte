// swift-tools-version: 6.4

import PackageDescription

// Le code audio repris de Cairn reste en mode Swift 5 : voir docs/rapport-cairn.md.
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Aparte",
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "Aparte", targets: ["AparteApp"]),
        .library(name: "Transcription", targets: ["Transcription"]),
        .library(name: "Capture", targets: ["Capture"]),
        .library(name: "Stockage", targets: ["Stockage"]),
        .library(name: "Analyse", targets: ["Analyse"]),
        .library(name: "DA", targets: ["DA"]),
        .library(name: "Interface", targets: ["Interface"]),
    ],
    dependencies: [
        // La séparation des voix, sur l'appareil, comme dans Cairn. Accord de Steven du 2 novembre 2026.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.16.1", traits: []),
    ],
    targets: [
        .target(name: "Transcription", swiftSettings: swift5),
        .target(name: "Capture", swiftSettings: swift5),
        .target(name: "Voix", dependencies: ["Transcription", .product(name: "FluidAudio", package: "FluidAudio")], swiftSettings: swift5),
        .target(name: "Stockage", dependencies: ["Transcription"]),
        .target(name: "Analyse", dependencies: ["Transcription", "Stockage"]),
        .target(name: "DA", resources: [.copy("Polices")]),
        .target(name: "Interface", dependencies: ["Transcription", "Capture", "Stockage", "Analyse", "DA", "Voix"]),
        .executableTarget(name: "AparteApp", dependencies: ["Interface"]),
        .testTarget(name: "TranscriptionTests", dependencies: ["Transcription"]),
        .testTarget(name: "CaptureTests", dependencies: ["Capture"]),
        .testTarget(name: "StockageTests", dependencies: ["Stockage"]),
        .testTarget(name: "AnalyseTests", dependencies: ["Analyse"]),
        .testTarget(name: "DATests", dependencies: ["DA"]),
        .testTarget(name: "InterfaceTests", dependencies: ["Interface"]),
    ]
)
