// KeyProbe: which SyncKey is usable after a draft Sync Add on this gateway?
import EASAdapter
import EASClient
import Foundation

@main
struct KeyProbe {
    static func main() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var values: [String: String] = [:]
        if let text = try? String(contentsOfFile: home + "/.uumail.env", encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty, !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { continue }
                var v = String(t[t.index(after: eq)...])
                if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
                values[String(t[..<eq])] = v
            }
        }
        guard let host = values["EAS_HOST"], let user = values["EAS_USER"], let pass = values["EAS_PASS"],
              let deviceID = values["EAS_DEVICE_ID"] else { print("KEYPROBE config missing"); exit(2) }
        let email = values["EAS_EMAIL"].flatMap { $0.isEmpty ? nil : $0 } ?? user
        let config = EASConfiguration(host: host, account: user, password: pass,
                                      domain: values["EAS_DOMAIN"] ?? "", deviceID: deviceID)
        let client = EASClient(configuration: config, transport: URLSessionTransport(configuration: config))
        let marker = "uumail key probe \(Int(Date().timeIntervalSince1970))"
        do {
            let bootstrap = try await client.sync(collectionID: "4", syncKey: "0")
            let key0 = bootstrap.syncKey
            print("KEYPROBE bootstrap key=\(key0)")
            let created = try await client.createDraft(
                EASDraft(to: email, cc: nil, subject: marker, bodyHTML: "<p>\(marker)</p>"),
                collectionID: "4", syncKey: key0, clientID: UUID().uuidString
            )
            print("KEYPROBE add key=\(created.syncKey) serverID=\(created.serverID ?? "nil")")
            func check(_ label: String, _ key: String) async {
                do {
                    let delta = try await client.sync(collectionID: "4", syncKey: key)
                    print("KEYPROBE \(label) key=\(key) OK next=\(delta.syncKey) added=\(delta.added.count)")
                } catch {
                    print("KEYPROBE \(label) key=\(key) FAILED \(String(describing: error))")
                }
            }
            await check("pre-write", key0)
            await check("add-response", created.syncKey)
            // Re-bootstrap from zero and see whether the item shows up.
            if let again = try? await client.sync(collectionID: "4", syncKey: "0") {
                print("KEYPROBE rebootstrap key=\(again.syncKey)")
                await check("rebootstrap", again.syncKey)
            }
            // Cleanup with a fresh bootstrap key.
            if let sid = created.serverID, let fresh = try? await client.sync(collectionID: "4", syncKey: "0") {
                do {
                    _ = try await client.deleteDraft(serverID: sid, collectionID: "4", syncKey: fresh.syncKey)
                    print("KEYPROBE cleanup delete ok")
                } catch {
                    print("KEYPROBE cleanup delete FAILED \(String(describing: error))")
                }
            }
        } catch {
            print("KEYPROBE ERROR \(String(describing: error))")
        }
    }
}
