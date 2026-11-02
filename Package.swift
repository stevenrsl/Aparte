// swift-tools-version: 6.4

import PackageDescription

let modules = ["Transcription", "Capture", "Stockage", "Analyse", "DA", "Interface"]

let package = Package(
    name: "Aparte",
    platforms: [.macOS(.v27)],
    products: modules.map { .library(name: $0, targets: [$0]) },
    targets: modules.flatMap { module in
        [
            .target(name: module),
            .testTarget(name: "\(module)Tests", dependencies: [.target(name: module)]),
        ]
    }
)
