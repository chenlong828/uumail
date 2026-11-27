// EmptyTest: does the Drafts window sync work only when the folder has items?
import EASClient
import Foundation

@main
struct EmptyTest {
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
              let deviceID = v["EAS_DEVICE_ID"] else { print("EMPTY config missing"); exit(2) }
        let email = v["EAS_EMAIL"].flatMap { $0.isEmpty ? nil : $0 } ?? user
        let config = EASConfiguration(host: host, account: user, password: pass,
                                      domain: v["EAS_DOMAIN"] ?? "", deviceID: deviceID)
        let client = EASClient(configuration: config, transport: URLSessionTransport(configuration: config))
        var created: String?
        do {
            let b = try await client.sync(collectionID: "4", syncKey: "0")
            let c = try await client.createDraft(
                EASDraft(to: email, cc: nil, subject: "uumail empty test", bodyHTML: "<p>e</p>"),
                collectionID: "4", syncKey: b.syncKey, clientID: UUID().uuidString
            )
            created = c.serverID
            print("EMPTY created \(c.serverID ?? "nil") addKey=\(c.syncKey)")
            let b2 = try await client.sync(collectionID: "4", syncKey: "0")
            do {
                let w = try await client.sync(collectionID: "4", syncKey: b2.syncKey)
                print("EMPTY window after create added=\(w.added.count) key=\(w.syncKey)")
            } catch { print("EMPTY window after create failed \(String(describing: error))") }
        } catch { print("EMPTY ERROR \(String(describing: error))") }
        if let sid = created {
            let b3 = try? await client.sync(collectionID: "4", syncKey: "0")
            if let b3 {
                if (try? await client.deleteDraft(serverID: sid, collectionID: "4", syncKey: b3.syncKey)) != nil {
                    print("EMPTY cleanup deleted")
                } else { print("EMPTY cleanup failed") }
            }
        }
    }
}
