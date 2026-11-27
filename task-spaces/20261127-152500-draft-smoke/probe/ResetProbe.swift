// ResetProbe: try folder resync + repeated bootstrap before reading Drafts.
import EASClient
import Foundation

@main
struct ResetProbe {
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
              let deviceID = v["EAS_DEVICE_ID"] else { print("RESET config missing"); exit(2) }
        let config = EASConfiguration(host: host, account: user, password: pass,
                                      domain: v["EAS_DOMAIN"] ?? "", deviceID: deviceID)
        let client = EASClient(configuration: config, transport: URLSessionTransport(configuration: config))
        do {
            let folders = try await client.folderSync(syncKey: "0")
            let drafts = folders.folders.first { $0.type == 3 }
            print("RESET folderSync ok, folders=\(folders.folders.count) drafts=\(drafts?.serverID ?? "nil") key=\(folders.syncKey)")
            for attempt in 1...3 {
                do {
                    let b = try await client.sync(collectionID: "4", syncKey: "0")
                    print("RESET attempt \(attempt) bootstrap=\(b.syncKey) added=\(b.added.count)")
                    let w = try await client.sync(collectionID: "4", syncKey: b.syncKey)
                    print("RESET attempt \(attempt) window added=\(w.added.count) key=\(w.syncKey)")
                    for m in w.added where (m.subject ?? "").contains("uumail") {
                        print("RESET leftover \(m.serverID) \(m.subject ?? "")")
                    }
                    break
                } catch {
                    print("RESET attempt \(attempt) FAILED \(String(describing: error))")
                    try await Task.sleep(for: .seconds(3))
                }
            }
        } catch {
            print("RESET folderSync FAILED \(String(describing: error))")
        }
    }
}
