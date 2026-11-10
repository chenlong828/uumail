import AppServices
import Darwin
import EASClient
import Foundation
import MailStore
import SyncEngine

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

        case "send":
            guard let to = value(of: "--to", in: arguments) else {
                FileHandle.standardError.write(Data("send: --to <address> is required\n".utf8))
                exit(2)
            }
            let service = try MailService(
                configuration: configuration,
                databasePath: value(of: "--db", in: arguments) ?? ".build/outbox.sqlite"
            )
            let draft = MailDraft(
                to: to,
                cc: nil,
                subject: value(of: "--subject", in: arguments) ?? "uumail 测试",
                body: value(of: "--body", in: arguments) ?? "这是一封来自 uumail 的测试邮件。"
            )
            do {
                let id = try await service.send(draft)
                print("sent: outbox \(id) cleared")
            } catch let error as MailGatewayError {
                print("send failed: \(error) (item kept for retry)")
                exit(3)
            }

        case "body":
            guard let folder = value(of: "--folder", in: arguments),
                  let server = value(of: "--server", in: arguments) else {
                FileHandle.standardError.write(Data("body: --folder <id> --server <id> are required\n".utf8))
                exit(2)
            }
            if let path = value(of: "--db", in: arguments) {
                // Goes through the real composition root, so the store side of the read
                // path (HTML conversion + body table) is exercised too.
                let service = try MailService(configuration: configuration, databasePath: path)
                let stored = try await service.fetchBody(folderID: folder, serverID: server)
                let cached = try service.body(folderID: folder, serverID: server) ?? ""
                print("body: truncated=\(stored.isTruncated) chars=\(stored.html.count) stored=\(cached.count)")
                print(stored.html.prefix(1_000))
                exit(0)
            }
            let fetched = try await client.fetchBody(collectionID: folder, serverID: server)
            print("body: type=\(fetched.isHTML ? "html" : "text") truncated=\(fetched.isTruncated) chars=\(fetched.payload.count)")
            print(fetched.payload.prefix(3_000))

        case "ping":
            let heartbeat = Int(value(of: "--heartbeat", in: arguments) ?? "10") ?? 10
            let folders = try await client.folderSync()
            guard let inbox = folders.folders.first(where: { $0.type == 2 }) else {
                print("no inbox")
                exit(2)
            }
            let started = Date()
            let result = try await client.ping(collectionID: inbox.serverID, heartbeatSeconds: heartbeat)
            let elapsed = Int(Date().timeIntervalSince(started))
            print("ping: status=\(result.status) changes=\(result.hasChanges) elapsed=\(elapsed)s heartbeat=\(heartbeat)s")
            exit(0)

        case "seed":
            // Writes the account into the login Keychain so the app starts configured.
            // The password never touches a file: it comes from the environment.
            let saved = StoredAccountConfiguration(
                host: configuration.host,
                account: configuration.account,
                password: configuration.password,
                domain: configuration.domain,
                deviceID: configuration.deviceID,
                displayName: configuration.account
            )
            try KeychainAccountStore().save(saved)
            print("keychain seeded: \(configuration.account)@\(configuration.host)")

        case "sync":
            guard let path = value(of: "--db", in: arguments) else {
                FileHandle.standardError.write(Data("sync: --db <path> is required\n".utf8))
                exit(2)
            }
            let service = try MailService(configuration: configuration, databasePath: path)
            do {
                let report = try await service.syncOnce()
                print("synced: \(report.folders) folders, +\(report.added) added, ~\(report.changed) changed, -\(report.removed) removed, \(report.rounds) rounds, key \(report.syncKey)")
            } catch let error as MailGatewayError {
                print("sync failed: \(error)")
                exit(3)
            }
            if let inbox = try service.folders().first(where: { $0.type == 2 }) {
                let stored = try service.messages(folderID: inbox.serverID, limit: 10)
                print("latest \(stored.count) in \(inbox.displayName):")
                for message in stored {
                    print("  [\(message.receivedRaw ?? "")] \(message.subject ?? "(no subject)") <- \(message.sender ?? "")")
                }
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
          send --to <addr> [--subject s] [--body b] [--db path]   send one message
          body --folder <id> --server <id> [--db path]   fetch one body; with --db also store it
          ping [--heartbeat N] long-poll the inbox and report status/elapsed
          seed                 store the env account in the login Keychain
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
