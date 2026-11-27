// KeyProbe2: key semantics around a draft Delete on this gateway.
import EASClient
import Foundation

@main
struct KeyProbe2 {
    static func main() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var v: [String: String] = [:]
        if let text = try? String(contentsOfFile: home + "/.uumail.env", encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty, !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { continue }
                var val = String(t[t.index(after: eq)...])
                if val.hasPrefix("\""), val.hasSuffix("\""), val.count >= 2 { val = String(val.dropFirst().dropLast()) }
                v[String(t[..<eq])] = val
            }
        }
        guard let host = v["EAS_HOST"], let user = v["EAS_USER"], let pass = v["EAS_PASS"],
              let deviceID = v["EAS_DEVICE_ID"] else { print("P2 config missing"); exit(2) }
        let email = v["EAS_EMAIL"].flatMap { $0.isEmpty ? nil : $0 } ?? user
        let config = EASConfiguration(host: host, account: user, password: pass,
                                      domain: v["EAS_DOMAIN"] ?? "", deviceID: deviceID)
        let client = EASClient(configuration: config, transport: URLSessionTransport(configuration: config))

        func syncKey(_ label: String) async -> String? {
            do {
                let r = try await client.sync(collectionID: "4", syncKey: "0")
                print("P2 \(label) bootstrap=\(r.syncKey)")
                return r.syncKey
            } catch { print("P2 \(label) bootstrap FAILED \(String(describing: error))"); return nil }
        }
        func check(_ label: String, _ key: String) async {
            do {
                let d = try await client.sync(collectionID: "4", syncKey: key)
                print("P2 \(label) key=\(key) OK next=\(d.syncKey) added=\(d.added.count)")
            } catch { print("P2 \(label) key=\(key) FAILED \(String(describing: error))") }
        }

        guard let k0 = await syncKey("start") else { exit(1) }
        await check("start", k0)
        var createdID: String?
        var deleteKey: String?
        do {
            let c = try await client.createDraft(
                EASDraft(to: email, cc: nil, subject: "uumail key2 probe", bodyHTML: "<p>p2</p>"),
                collectionID: "4", syncKey: k0, clientID: UUID().uuidString
            )
            createdID = c.serverID
            print("P2 addKey=\(c.syncKey) serverID=\(c.serverID ?? "nil")")
            let k1 = await syncKey("after-add")
            if let k1 { await check("after-add", k1) }
            if let k1, let sid = c.serverID {
                let del = try await client.deleteDraft(serverID: sid, collectionID: "4", syncKey: k1)
                deleteKey = del.syncKey
                createdID = nil
                print("P2 deleteKey=\(del.syncKey)")
                let k2 = await syncKey("after-delete")
                if let k2 { await check("after-delete-bootstrap", k2) }
                await check("after-delete-writekey", del.syncKey)
            }
        } catch { print("P2 ERROR \(String(describing: error))") }
        // Best-effort cleanup if something was left.
        if let createdID, let k = await syncKey("cleanup") {
            if let _ = try? await client.deleteDraft(serverID: createdID, collectionID: "4", syncKey: k) {
                print("P2 cleanup deleted \(createdID)")
            } else { print("P2 cleanup FAILED \(createdID)") }
        }
        _ = deleteKey
    }
}
