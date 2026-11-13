import Composition
import Darwin
import EASClient
import Foundation
import MailDomain
import Scenes

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
        let easConfiguration = CommandLineComposition.easConfiguration(configuration)
        let client = EASClient(
            configuration: easConfiguration,
            transport: URLSessionTransport(configuration: easConfiguration)
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
            // Local read through the read scene: a missing store is bootstrapped once with
            // the account's folder snapshot, then the folders come from the store.
            let composition = try await CommandLineComposition.make(
                databasePath: value(of: "--db", in: arguments) ?? defaultDatabasePath,
                configuration: configuration
            )
            let folders = try composition.read.folders()
            if flags.contains("--json") {
                let rows = folders.map { folder in
                    ["id": folder.serverID, "parent": folder.parentID ?? "", "name": folder.displayName, "type": String(folder.type)]
                }
                let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
                print(String(decoding: data, as: UTF8.self))
            } else {
                for folder in folders.sorted(by: { ($0.type, $0.displayName) < ($1.type, $1.displayName) }) {
                    print("[\(folder.type)] \(folder.serverID)\t\(folder.displayName)")
                }
            }
            let syncKey = try composition.store.syncKey(account: composition.account, collection: "folders")
            print("sync key: \(syncKey ?? "(unknown)"), \(folders.count) folders")

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
            let composition = try await CommandLineComposition.make(
                databasePath: value(of: "--db", in: arguments) ?? ".build/outbox.sqlite",
                configuration: configuration
            )
            let draft = Draft(
                to: to,
                cc: nil,
                subject: value(of: "--subject", in: arguments) ?? "uumail 测试",
                body: value(of: "--body", in: arguments) ?? "这是一封来自 uumail 的测试邮件。"
            )
            let id: OutboxID
            do {
                id = try await composition.compose.send(draft, account: composition.account)
            } catch {
                print("send failed: \(error)")
                exit(3)
            }
            let outcomes = await composition.outbox.flushAll(account: composition.account)
            if let failure = outcomes.first(where: { $0.outboxID == id })?.error {
                print("send failed: \(failure) (item kept for retry)")
                exit(3)
            }
            print("sent: outbox \(id) cleared")

        case "body":
            guard let folder = value(of: "--folder", in: arguments),
                  let server = value(of: "--server", in: arguments) else {
                FileHandle.standardError.write(Data("body: --folder <id> --server <id> are required\n".utf8))
                exit(2)
            }
            if let path = value(of: "--db", in: arguments) {
                // Goes through the real composition root, so the store side of the read
                // path (HTML conversion + body table) is exercised too.
                let composition = try await CommandLineComposition.make(
                    databasePath: path,
                    configuration: configuration
                )
                let ref = MessageRef(folderID: folder, serverID: server)
                var html: String?
                var truncated = false
                var failure: MailError?
                for await event in composition.read.open(ref) {
                    switch event {
                    case .cached(let cachedHTML):
                        html = cachedHTML
                    case .loaded(let fetched):
                        html = fetched.text
                        truncated = fetched.isTruncated
                    case .failed(let error):
                        failure = error
                    }
                }
                if let failure {
                    print("body failed: \(failure)")
                    exit(3)
                }
                let cached = (try? composition.read.bodyIfCached(ref)) ?? nil
                print("body: truncated=\(truncated) chars=\(html?.count ?? 0) stored=\(cached?.count ?? 0)")
                print((html ?? "").prefix(1_000))
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
            try KeychainCredentialStore().save(configuration)
            print("keychain seeded: \(configuration.account)@\(configuration.host)")

        case "sync":
            guard let path = value(of: "--db", in: arguments) else {
                FileHandle.standardError.write(Data("sync: --db <path> is required\n".utf8))
                exit(2)
            }
            let composition = try await CommandLineComposition.make(
                databasePath: path,
                configuration: configuration
            )
            let outcome = await composition.sync.refresh()
            if let report = outcome.report {
                print("synced: \(report.folders) folders, +\(report.added) added, ~\(report.changed) changed, -\(report.removed) removed, \(report.rounds) rounds, key \(report.syncKey)")
            } else {
                print("sync failed: \(String(describing: outcome.error))")
                exit(3)
            }
            if let inbox = try composition.read.folders().first(where: { $0.type == 2 }) {
                let stored = try composition.read.messages(folderID: inbox.serverID, limit: 10)
                print("latest \(stored.count) in \(inbox.displayName):")
                for message in stored {
                    print("  [\(message.receivedRaw ?? "")] \(message.subject ?? "(no subject)") <- \(message.sender ?? "")")
                }
            }

        case "store":
            // Persists a folder snapshot into a local SQLite file, proving the store contract:
            // the composition bootstraps the account row and snapshot, the read scene prints it.
            guard let path = value(of: "--db", in: arguments) else {
                FileHandle.standardError.write(Data("store: --db <path> is required\n".utf8))
                exit(2)
            }
            let composition = try await CommandLineComposition.make(
                databasePath: path,
                configuration: configuration
            )
            let stored = try composition.read.folders()
            print("stored \(stored.count) folders for \(composition.account) in \(path)")
            for folder in stored {
                print("  [\(folder.type)] \(folder.displayName)")
            }

        default:
            printUsage()
            exit(2)
        }
    }

    private static let defaultDatabasePath = ".build/uumailctl.sqlite"

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func loadConfiguration(insecure: Bool) throws -> ServerConfiguration {
        try CommandLineComposition.configuration(
            environment: ProcessInfo.processInfo.environment,
            insecure: insecure
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
          folders [--json] [--db path]   list the folders in the local store
          diagnose             OPTIONS -> Provision -> FolderSync
          send --to <addr> [--subject s] [--body b] [--db path]   send one message
          body --folder <id> --server <id> [--db path]   fetch one body; with --db also store it
          ping [--heartbeat N] long-poll the inbox and report status/elapsed
          seed                 store the env account in the login Keychain
          store --db <path>    bootstrap a local SQLite store with the folder snapshot
          sync --db <path>     sync the inbox into the store (read-only on the server)

        Data commands take --db <path>; folders defaults to .build/uumailctl.sqlite and
        send to .build/outbox.sqlite. Do not point two processes at the running app database.

        Flags:
          --insecure           skip TLS verification (only for internal CAs)
        """)
    }
}
