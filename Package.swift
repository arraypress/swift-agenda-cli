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
        .package(url: "https://github.com/arraypress/swift-cli-kit.git", from: "0.20.0"),
        .package(url: "https://github.com/arraypress/swift-agenda-kit.git", from: "0.3.0"),
        // Tags are written through a helper shortcut (EventKit has no tag API).
        .package(url: "https://github.com/arraypress/swift-apple-shortcuts.git", from: "0.1.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        .executableTarget(
            name: "agenda",
            dependencies: [
                .product(name: "AgendaKit", package: "swift-agenda-kit"),
                .product(name: "AppleShortcuts", package: "swift-apple-shortcuts"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "CLIKit", package: "swift-cli-kit"),
            ],
            path: "Sources/agenda",
            exclude: ["Info.plist"],
            swiftSettings: [
                // CLIKit (0.13.1+) builds with this, so `CLICommand.execute()` is
                // nonisolated(nonsending); a conformer compiled without it sends `self`
                // across an isolation boundary on every await and Swift 6 refuses.
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ],
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

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
