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
        .target(
            name: "AppServices",
            dependencies: ["EASAdapter", "EASClient", "MailDomain", "MailStore", "SyncEngine"]
        ),
        .executableTarget(
            name: "uumail",
            dependencies: ["AppServices", "MailStore"],
            swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
        ),
        .executableTarget(
            name: "uumailctl",
            dependencies: ["EASClient", "MailStore", "SyncEngine", "AppServices"]
        ),
        .testTarget(name: "EASClientTests", dependencies: ["EASClient"]),
        .testTarget(name: "MailDomainTests", dependencies: ["MailDomain"]),
        .testTarget(name: "EASAdapterTests", dependencies: ["EASAdapter", "EASClient", "MailDomain"]),
        .testTarget(name: "MailStoreTests", dependencies: ["MailStore"]),
        .testTarget(name: "SyncEngineTests", dependencies: ["SyncEngine"]),
        .testTarget(name: "AppServicesTests", dependencies: ["AppServices"]),
    ]
)
