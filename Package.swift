// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Salvo",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "SalvoApp", targets: ["SalvoApp"]),
        .library(name: "CoderAPI", targets: ["CoderAPI"]),
        .library(name: "GmailAPI", targets: ["GmailAPI"]),
    ],
    targets: [
        .executableTarget(
            name: "SalvoApp",
            dependencies: ["CoderAPI", "GmailAPI"]
        ),
        .target(name: "CoderAPI"),
        .target(name: "GmailAPI"),
        .testTarget(
            name: "CoderAPITests",
            dependencies: ["CoderAPI"]
        ),
    ]
)
