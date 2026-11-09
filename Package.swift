// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "uumail",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EASClient", targets: ["EASClient"]),
        .library(name: "MailStore", targets: ["MailStore"]),
        .library(name: "SyncEngine", targets: ["SyncEngine"]),
        .executable(name: "uumailctl", targets: ["uumailctl"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.12.0"),
    ],
    targets: [
        .target(
            name: "EASClient",
            resources: [.process("Resources")]
        ),
        .target(
            name: "MailStore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "SyncEngine"),
        .executableTarget(
            name: "uumailctl",
            dependencies: ["EASClient", "MailStore", "SyncEngine"]
        ),
        .testTarget(name: "EASClientTests", dependencies: ["EASClient"]),
        .testTarget(name: "MailStoreTests", dependencies: ["MailStore"]),
        .testTarget(name: "SyncEngineTests", dependencies: ["SyncEngine"]),
    ]
)
