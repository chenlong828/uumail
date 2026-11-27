// RecoveryProbe: find a usable SyncKey for the Drafts collection, or a handshake that yields one.
import EASClient
import Foundation

@main
struct RecoveryProbe {
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
              let deviceID = v["EAS_DEVICE_ID"] else { print("REC config missing"); exit(2) }
        let config = EASConfiguration(host: host, account: user, password: pass,
                                      domain: v["EAS_DOMAIN"] ?? "", deviceID: deviceID)
        let client = EASClient(configuration: config, transport: URLSessionTransport(configuration: config))
        let known = ["1208799361", "54941921", "1281471613", "1540195559", "401846129", "1610833229",
                     "1828824439", "1333301643", "485035375", "622324582", "1689443747"]
        for key in known {
            do {
                let d = try await client.sync(collectionID: "4", syncKey: key)
                print("REC key \(key) OK added=\(d.added.count) next=\(d.syncKey)")
            } catch {
                print("REC key \(key) failed \(String(describing: error))")
            }
        }
        for (window, filter, preview) in [(1, 0, 0), (25, 0, 0), (25, 5, 500)] {
            do {
                let b = try await client.sync(
                    collectionID: "4", syncKey: "0", window: window,
                    filterType: filter, bodyPreviewCharacters: preview
                )
                print("REC handshake w=\(window) f=\(filter) p=\(preview) key=\(b.syncKey) added=\(b.added.count)")
                do {
                    let w = try await client.sync(collectionID: "4", syncKey: b.syncKey)
                    print("REC   follow window added=\(w.added.count) key=\(w.syncKey)")
                } catch {
                    print("REC   follow failed \(String(describing: error))")
                }
            } catch {
                print("REC handshake w=\(window) f=\(filter) p=\(preview) failed \(String(describing: error))")
            }
        }
    }
}
