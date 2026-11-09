import Darwin
import EASClient
import Foundation
import MailStore

@main
struct UumailCtl {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch let error as EASError {
            FileHandle.standardError.write(Data("EAS error: \(error)\n".utf8))
            exit(3)
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(3)
        }
    }

    private static func run(arguments: [String]) async throws {
        guard let command = arguments.first else {
            printUsage()
            exit(2)
        }
        let flags = Set(arguments.dropFirst().filter { $0.hasPrefix("--") })
        let configuration = try loadConfiguration(insecure: flags.contains("--insecure"))
        let client = EASClient(
            configuration: configuration,
            transport: URLSessionTransport(configuration: configuration)
        )

        switch command {
        case "options":
            let capabilities = try await client.options()
            print("protocol versions: \(capabilities.protocolVersions.joined(separator: ", "))")
            print("commands: \(capabilities.commands.count)")
            print(capabilities.commands.joined(separator: ", "))

        case "provision":
            let key = try await client.provision()
            print("policy key acquired (\(key.count) chars)")

        case "folders":
            let result = try await client.folderSync()
            if flags.contains("--json") {
                let rows = result.folders.map { folder in
                    ["id": folder.serverID, "parent": folder.parentID ?? "", "name": folder.displayName, "type": String(folder.type)]
                }
                let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
                print(String(decoding: data, as: UTF8.self))
            } else {
                for folder in result.folders.sorted(by: { $0.type < $1.type }) {
                    print("[\(folder.type)] \(folder.serverID)\t\(folder.displayName)")
                }
            }
            print("sync key: \(result.syncKey), \(result.folders.count) folders")

        case "diagnose":
            let capabilities = try await client.options()
            print("[1] OPTIONS ok: \(capabilities.protocolVersions.joined(separator: ", "))")
            let key = try await client.provision()
            print("[2] Provision ok: policy key \(key.count) chars")
            let result = try await client.folderSync()
            print("[3] FolderSync ok: \(result.folders.count) folders, key \(result.syncKey)")
            if let inbox = result.folders.first(where: { $0.type == 2 }) {
                print("[4] inbox: id=\(inbox.serverID) name=\(inbox.displayName)")
            } else {
                print("[4] inbox: NOT FOUND")
            }

        case "sync":
            // Composition-root glue for the probe stage: wires the gateway to the store
            // directly. The SyncEngine component replaces this once it exists.
            guard let path = value(of: "--db", in: arguments) else {
                FileHandle.standardError.write(Data("sync: --db <path> is required\n".utf8))
                exit(2)
            }
            let store = try MailStore(path: path)
            let accountID = try existingOrNewAccount(store: store, configuration: configuration)

            if try store.folders(account: accountID).isEmpty {
                let folders = try await client.folderSync()
                try store.applyFolderSnapshot(
                    account: accountID,
                    folders: folders.folders.map {
                        MailFolder(serverID: $0.serverID, parentID: $0.parentID, displayName: $0.displayName, type: $0.type)
                    },
                    syncKey: folders.syncKey
                )
                print("folders: \(folders.folders.count) stored")
            }

            guard let inbox = try store.folders(account: accountID).first(where: { $0.type == 2 }) else {
                FileHandle.standardError.write(Data("sync: no inbox folder\n".utf8))
                exit(2)
            }

            var key = try store.syncKey(account: accountID, collection: inbox.serverID) ?? "0"

            if key == "0" {
                // First sync: `SyncKey=0` answers with a fresh key and no items. The window
                // only arrives on the follow-up call, so both requests finish before any
                // write — advancing the key without its window would silently skip mail.
                let bootstrap = try await client.sync(collectionID: inbox.serverID, syncKey: "0")
                let window = try await client.sync(collectionID: inbox.serverID, syncKey: bootstrap.syncKey)
                try store.applySyncBatch(
                    account: accountID,
                    folder: inbox.serverID,
                    added: window.added.map(Self.mailMessage),
                    changed: window.changed.map(Self.mailMessage),
                    removedServerIDs: window.removedServerIDs,
                    syncKey: window.syncKey
                )
                print("initial sync: +\(window.added.count) added, key \(window.syncKey), more=\(window.moreAvailable)")
                key = window.syncKey
            }

            for round in 1...5 {
                let delta = try await client.sync(collectionID: inbox.serverID, syncKey: key)
                try store.applySyncBatch(
                    account: accountID,
                    folder: inbox.serverID,
                    added: delta.added.map(Self.mailMessage),
                    changed: delta.changed.map(Self.mailMessage),
                    removedServerIDs: delta.removedServerIDs,
                    syncKey: delta.syncKey
                )
                print("round \(round): +\(delta.added.count) added, -\(delta.removedServerIDs.count) removed, key \(delta.syncKey), more=\(delta.moreAvailable)")
                key = delta.syncKey
                if !delta.moreAvailable { break }
            }
            let stored = try store.messages(account: accountID, folder: inbox.serverID, limit: 20)
            print("stored \(stored.count) messages in \(inbox.displayName)")
            for message in stored.prefix(10) {
                print("  [\(message.receivedRaw ?? "")] \(message.subject ?? "(no subject)") <- \(message.sender ?? "")")
            }

        case "store":
            // Persists a folder snapshot into a local SQLite file, proving the store contract.
            guard let path = value(of: "--db", in: arguments) else {
                FileHandle.standardError.write(Data("store: --db <path> is required\n".utf8))
                exit(2)
            }
            let result = try await client.folderSync()
            let store = try MailStore(path: path)
            let accountID = try store.createAccount(
                NewAccount(
                    displayName: configuration.account,
                    address: "\(configuration.account)@\(configuration.host)",
                    host: configuration.host
                )
            )
            try store.applyFolderSnapshot(
                account: accountID,
                folders: result.folders.map {
                    MailFolder(serverID: $0.serverID, parentID: $0.parentID, displayName: $0.displayName, type: $0.type)
                },
                syncKey: result.syncKey
            )
            let stored = try store.folders(account: accountID)
            print("stored \(stored.count) folders for \(accountID) in \(path)")
            for folder in stored {
                print("  [\(folder.type)] \(folder.displayName)")
            }

        default:
            printUsage()
            exit(2)
        }
    }

    private static func existingOrNewAccount(store: MailStore, configuration: EASConfiguration) throws -> AccountID {
        if let first = try store.accounts().first {
            return first
        }
        return try store.createAccount(
            NewAccount(
                displayName: configuration.account,
                address: "\(configuration.account)@\(configuration.host)",
                host: configuration.host
            )
        )
    }

    private static func mailMessage(_ message: EASMessage) -> MailMessage {
        MailMessage(
            serverID: message.serverID,
            subject: message.subject,
            sender: message.from,
            recipients: message.to,
            receivedRaw: message.dateReceived,
            isRead: message.isRead ?? false,
            importance: message.importance,
            bodyPreview: message.bodyPreview
        )
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func loadConfiguration(insecure: Bool) throws -> EASConfiguration {
        let env = ProcessInfo.processInfo.environment
        func require(_ key: String) throws -> String {
            guard let value = env[key], !value.isEmpty else {
                throw ConfigurationError.missing(key)
            }
            return value
        }
        return EASConfiguration(
            host: try require("EAS_HOST"),
            account: try require("EAS_USER"),
            password: try require("EAS_PASS"),
            domain: env["EAS_DOMAIN"] ?? "",
            deviceID: try require("EAS_DEVICE_ID"),
            allowInsecureTLS: insecure
        )
    }

    static func printUsage() {
        print("""
        uumailctl — EAS diagnostics

        Environment:
          EAS_HOST, EAS_USER, EAS_PASS, EAS_DOMAIN, EAS_DEVICE_ID

        Commands:
          options              ask the gateway which protocol versions and commands it allows
          provision            run the two-step policy handshake
          folders [--json]     list the folder hierarchy
          diagnose             OPTIONS -> Provision -> FolderSync
          store --db <path>    sync folders into a local SQLite store
          sync --db <path>     sync the inbox into the store (read-only on the server)

        Flags:
          --insecure           skip TLS verification (only for internal CAs)
        """)
    }
}

enum ConfigurationError: Error, CustomStringConvertible {
    case missing(String)

    var description: String {
        switch self {
        case .missing(let key): "missing environment variable \(key)"
        }
    }
}
