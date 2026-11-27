// DraftSmoke: real-gateway smoke for REQ-0044. Creates a local draft in a TEMPORARY store,
// lets SyncEngine upload it to the server Drafts folder, verifies the server copy by
// fetching its body, then deletes the local row (tombstone) and verifies the server copy
// is gone. Secrets are read from ~/.uumail.env (fallback: the project .env) and never
// printed.
import EASAdapter
import EASClient
import Foundation
import MailDomain
import MailStore
import SyncContract
import SyncEngine

struct SmokeFailure: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { "SmokeFailure(\(message))" }
}

func parseEnv(_ path: String) -> [String: String] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
    var values: [String: String] = [:]
    for line in text.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equal = trimmed.firstIndex(of: "=") else {
            continue
        }
        let key = String(trimmed[..<equal])
        var value = String(trimmed[trimmed.index(after: equal)...])
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        values[key] = value
    }
    return values
}

@main
struct DraftSmoke {
    static func main() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cwd = FileManager.default.currentDirectoryPath
        var values = parseEnv(home + "/.uumail.env")
        if values.isEmpty { values = parseEnv(cwd + "/.env") }
        guard let host = values["EAS_HOST"], let user = values["EAS_USER"],
              let password = values["EAS_PASS"], let deviceID = values["EAS_DEVICE_ID"]
        else {
            print("SMOKE config: missing EAS_HOST/USER/PASS/DEVICE_ID")
            exit(2)
        }
        let email = values["EAS_EMAIL"].flatMap { $0.isEmpty ? nil : $0 } ?? user
        let configuration = EASConfiguration(
            host: host, account: user, password: password,
            domain: values["EAS_DOMAIN"] ?? "", deviceID: deviceID, protocolVersion: "16.1"
        )
        let client = EASClient(
            configuration: configuration,
            transport: URLSessionTransport(configuration: configuration)
        )
        let adapter = EASAdapter(client: client)
        let marker = "uumail 草稿同步冒烟 \(Int(Date().timeIntervalSince1970))"

        var boundID: String?
        do {
            let path = NSTemporaryDirectory() + "uumail-draft-smoke-\(UUID().uuidString).sqlite"
            let store = try MailStore(path: path)
            let account = try store.createAccount(
                NewAccount(displayName: "smoke", address: email, host: host)
            )
            let engine = SyncEngine(
                gateway: adapter, store: store, account: account,
                writeGateway: adapter, draftStore: store
            )
            let localID = try store.outbox.saveDraft(
                account: account,
                draft: Draft(
                    to: email, cc: nil, subject: marker,
                    body: "uumail 草稿同步冒烟正文", isDraft: true,
                    bodyHTML: "<p>uumail 草稿同步冒烟正文</p>"
                )
            )
            print("SMOKE local draft: \(localID)")

            let upload = try await engine.syncDraftsOnce()
            print("SMOKE upload report: downloaded=\(upload?.downloaded ?? -1) uploaded=\(upload?.uploaded ?? -1) updated=\(upload?.updated ?? -1) deleted=\(upload?.deleted ?? -1)")
            let drafts = try store.outbox.drafts(account: account)
            guard let bound = drafts.first(where: { $0.id == localID }), let serverID = bound.serverID else {
                throw SmokeFailure("local draft was not bound to a server id")
            }
            boundID = serverID
            print("SMOKE bound serverID: \(serverID)")

            let folders = try store.folders(account: account)
            guard let draftsFolder = folders.first(where: { $0.isDrafts }) else {
                throw SmokeFailure("no drafts folder in the folder snapshot")
            }
            print("SMOKE drafts folder: \(draftsFolder.displayName) (\(draftsFolder.serverID))")

            let storedKey = try store.syncKey(account: account, collection: "4") ?? "nil"
            print("SMOKE stored drafts key after upload: \(storedKey)")
            do {
                let probeDelta = try await adapter.fetchMessages(
                    collectionID: "4", syncKey: storedKey, window: 25, filterType: 5
                )
                print("SMOKE pull after upload ok: added=\(probeDelta.added.count) key=\(probeDelta.syncKey)")
            } catch {
                print("SMOKE pull after upload failed: \(String(describing: error))")
            }
            let fetched = try await adapter.fetchBody(
                collectionID: draftsFolder.serverID, serverID: serverID
            )
            let present = fetched.text.contains("草稿同步冒烟")
            print("SMOKE server copy present after upload: \(present)")

            _ = try store.outbox.deleteDraft(account: account, draftID: localID)
            let deletion = try await engine.syncDraftsOnce()
            print("SMOKE delete report: deleted=\(deletion?.deleted ?? -1)")
            print("SMOKE tombstones left: \((try? store.outbox.draftTombstones(account: account))?.count ?? -1)")

            var gone = false
            for attempt in 0..<8 {
                do {
                    _ = try await adapter.fetchBody(collectionID: draftsFolder.serverID, serverID: serverID)
                    try await Task.sleep(for: .seconds(1.5))
                } catch {
                    gone = true
                    print("SMOKE server copy fetch failed after attempt \(attempt + 1): \(type(of: error))")
                    break
                }
            }
            print("SMOKE server copy gone after delete: \(gone)")
            guard present, gone else { throw SmokeFailure("upload/presence or delete check failed") }
            print("SMOKE PASS")
            exit(0)
        } catch {
            print("SMOKE ERROR: \(String(describing: error))")
            // Best effort: if a server draft was bound before the failure, delete it directly
            // so the smoke never leaves test mail behind.
            if let boundID {
                do {
                    let key = try await client.sync(collectionID: "4", syncKey: "0").syncKey
                    _ = try await client.deleteDraft(
                        serverID: boundID, collectionID: "4", syncKey: key
                    )
                    print("SMOKE cleanup: deleted leftover server draft")
                } catch {
                    print("SMOKE cleanup FAILED: \(String(describing: error))")
                }
            }
            exit(1)
        }
    }
}
