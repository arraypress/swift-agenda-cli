// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Agenda",
    platforms: [
        // macOS 15 is the floor so the full-access EventKit surface is available
        // unconditionally — no `if #available` fences around the modern APIs.
        // Spelled as a string because `.v15` only exists from tools-version 6.0.
        .macOS("15.0")
    ],
    products: [
        .executable(name: "agenda", targets: ["agenda"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/arraypress/swift-cli-kit.git", from: "0.4.0"),
        .package(url: "https://github.com/arraypress/swift-agenda-kit.git", from: "0.2.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        .executableTarget(
            name: "agenda",
            dependencies: [
                .product(name: "AgendaKit", package: "swift-agenda-kit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "CLIKit", package: "swift-cli-kit"),
            ],
            path: "Sources/agenda",
            exclude: ["Info.plist"],
            linkerSettings: [
                // A bare SPM executable has no bundle, so TCC finds no usage strings and
                // the EventKit prompt never appears. Embedding the plist in __TEXT gives
                // the binary the same purpose strings an .app would carry.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/agenda/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "AgendaCLITests",
            dependencies: [
                "agenda",
                .product(name: "AgendaKit", package: "swift-agenda-kit"),
                .product(name: "CLIKit", package: "swift-cli-kit"),
            ],
        ),
    ]
)
