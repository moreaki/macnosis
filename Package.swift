// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "macnosis",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "macnosis", targets: ["macnosis"]),
        .library(name: "MacnosisCore", targets: ["MacnosisCore"]),
    ],
    targets: [
        .target(name: "MacnosisCore"),
        .executableTarget(
            name: "macnosis",
            dependencies: ["MacnosisCore"]
        ),
        .testTarget(
            name: "MacnosisCoreTests",
            dependencies: ["MacnosisCore"]
        ),
        .testTarget(
            name: "macnosisTests",
            dependencies: ["macnosis", "MacnosisCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
