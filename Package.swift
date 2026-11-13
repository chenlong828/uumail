// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "uumail",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EASClient", targets: ["EASClient"]),
        .library(name: "MailDomain", targets: ["MailDomain"]),
        .library(name: "EASAdapter", targets: ["EASAdapter"]),
        .library(name: "MailStore", targets: ["MailStore"]),
        .library(name: "SyncEngine", targets: ["SyncEngine"]),
        .library(name: "Outbox", targets: ["Outbox"]),
        .library(name: "Scenes", targets: ["Scenes"]),
        .library(name: "Presentation", targets: ["Presentation"]),
        .library(name: "Composition", targets: ["Composition"]),
        .library(name: "AppServices", targets: ["AppServices"]),
        .executable(name: "uumail", targets: ["uumail"]),
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
        .target(name: "MailDomain"),
        .target(
            name: "EASAdapter",
            dependencies: ["EASClient", "MailDomain"]
        ),
        .target(
            name: "MailStore",
            dependencies: ["MailDomain", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "SyncEngine", dependencies: ["MailDomain"]),
        .target(name: "Outbox", dependencies: ["MailDomain", "MailStore"]),
        .target(
            name: "Scenes",
            dependencies: ["MailDomain", "MailStore", "SyncEngine", "Outbox"]
        ),
        .target(
            name: "Presentation",
            dependencies: ["MailDomain", "Scenes"]
        ),
        .target(
            name: "Composition",
            dependencies: [
                "EASAdapter", "EASClient", "MailDomain", "MailStore", "Outbox",
                "Presentation", "Scenes", "SyncEngine",
            ],
            swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
        ),
        .target(
            name: "AppServices",
            dependencies: ["EASAdapter", "EASClient", "MailDomain", "MailStore", "Outbox", "Scenes", "SyncEngine"]
        ),
        .executableTarget(
            name: "uumail",
            dependencies: ["Composition", "Presentation"],
            swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
        ),
        .executableTarget(
            name: "uumailctl",
            dependencies: ["EASClient", "MailStore", "SyncEngine", "AppServices"]
        ),
        .testTarget(name: "EASClientTests", dependencies: ["EASClient"]),
        .testTarget(name: "MailDomainTests", dependencies: ["MailDomain"]),
        .testTarget(name: "EASAdapterTests", dependencies: ["EASAdapter", "EASClient", "MailDomain"]),
        .testTarget(name: "CompositionTests", dependencies: ["Composition", "MailDomain"]),
        .testTarget(name: "MailStoreTests", dependencies: ["MailStore", "MailDomain"]),
        .testTarget(name: "OutboxTests", dependencies: ["Outbox", "MailStore", "MailDomain"]),
        .testTarget(name: "SyncEngineTests", dependencies: ["SyncEngine"]),
        .testTarget(name: "ScenesTests", dependencies: ["Scenes", "MailDomain", "MailStore", "SyncEngine", "Outbox"]),
        .testTarget(
            name: "PresentationTests",
            dependencies: ["Presentation", "Scenes", "MailDomain", "MailStore", "SyncEngine", "Outbox"]
        ),
        .testTarget(name: "AppServicesTests", dependencies: ["AppServices"]),
    ]
)
