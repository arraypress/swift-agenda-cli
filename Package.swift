// swift-tools-version: 5.9
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
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "AgendaKit",
            targets: ["AgendaKit"]),
        .executable(
            name: "agenda",
            targets: ["agenda"]),
    ],
    dependencies: [
        // Only the CLI target takes this on — `AgendaKit` stays Foundation + EventKit.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        .target(
            name: "AgendaKit",
            path: "Sources/AgendaKit"
        ),
        .executableTarget(
            name: "agenda",
            dependencies: [
                "AgendaKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
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
            name: "AgendaKitTests",
            dependencies: ["AgendaKit"],
            path: "Tests"
        ),
    ]
)
