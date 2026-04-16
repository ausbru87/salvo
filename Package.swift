// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CoderMail",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "CoderMailApp", targets: ["CoderMailApp"]),
        .library(name: "CoderAPI", targets: ["CoderAPI"]),
        .library(name: "GmailAPI", targets: ["GmailAPI"]),
    ],
    targets: [
        .executableTarget(
            name: "CoderMailApp",
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
