// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "uumail",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EASClient", targets: ["EASClient"]),
        .library(name: "MailDomain", targets: ["MailDomain"]),
        .library(name: "HTMLSupport", targets: ["HTMLSupport"]),
        .library(name: "EASAdapter", targets: ["EASAdapter"]),
        .library(name: "MailStore", targets: ["MailStore"]),
        .library(name: "SyncEngine", targets: ["SyncEngine"]),
        .library(name: "Outbox", targets: ["Outbox"]),
        .library(name: "Scenes", targets: ["Scenes"]),
        .library(name: "Presentation", targets: ["Presentation"]),
        .library(name: "Composition", targets: ["Composition"]),
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
        .target(name: "MeetingDomain"),
        .target(name: "SyncContract", dependencies: ["MailDomain", "MeetingDomain"]),
        .target(name: "HTMLSupport", dependencies: ["MailDomain"]),
        .target(
            name: "EASAdapter",
            dependencies: ["EASClient", "MailDomain", "MeetingDomain", "SyncContract"]
        ),
        .target(
            name: "MailStore",
            dependencies: ["MailDomain", "MeetingDomain", "SyncContract", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "SyncEngine", dependencies: ["MailDomain", "SyncContract"]),
        .target(name: "Outbox", dependencies: ["MailDomain", "MailStore", "SyncContract"]),
        .target(
            name: "Scenes",
            dependencies: ["MailDomain", "MeetingDomain", "MailStore", "SyncEngine", "Outbox", "HTMLSupport", "SyncContract"]
        ),
        .target(
            name: "Presentation",
            dependencies: ["MailDomain", "MeetingDomain", "Scenes", "HTMLSupport"]
        ),
        .target(
            name: "Composition",
            dependencies: [
                "EASAdapter", "EASClient", "MailDomain", "MailStore", "Outbox",
                "Presentation", "Scenes", "SyncContract", "SyncEngine",
            ],
            swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
        ),
        .executableTarget(
            name: "uumail",
            dependencies: ["Composition", "Presentation", "MeetingDomain"],
            swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
        ),
        .executableTarget(
            name: "uumailctl",
            dependencies: ["Composition", "EASClient", "MailDomain", "Scenes"]
        ),
        .testTarget(name: "EASClientTests", dependencies: ["EASClient"]),
        .testTarget(name: "MailDomainTests", dependencies: ["MailDomain", "MeetingDomain"]),
        .testTarget(name: "MeetingDomainTests", dependencies: ["MeetingDomain"]),
        .testTarget(name: "HTMLSupportTests", dependencies: ["HTMLSupport", "MailDomain"]),
        .testTarget(name: "EASAdapterTests", dependencies: ["EASAdapter", "EASClient", "MailDomain", "MeetingDomain"]),
        .testTarget(
            name: "CompositionTests",
            dependencies: ["Composition", "EASAdapter", "MailDomain", "MailStore", "Outbox", "Presentation", "SyncContract"]
        ),
        .testTarget(
            name: "MailStoreTests",
            dependencies: ["MailStore", "MailDomain", "MeetingDomain", "SyncContract", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "OutboxTests", dependencies: ["Outbox", "MailStore", "MailDomain", "SyncContract"]),
        .testTarget(name: "SyncEngineTests", dependencies: ["SyncEngine", "SyncContract"]),
        .testTarget(
            name: "ScenesTests",
            dependencies: [
                "Scenes", "MailDomain", "MeetingDomain", "MailStore", "SyncEngine", "Outbox", "HTMLSupport", "SyncContract",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "PresentationTests",
            dependencies: ["Presentation", "Scenes", "MailDomain", "MeetingDomain", "MailStore", "SyncEngine", "Outbox", "SyncContract"]
        ),
    ]
)
