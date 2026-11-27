import EASClient
import Foundation

@main
struct InboxProbe {
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
              let deviceID = v["EAS_DEVICE_ID"] else { print("INBOX config missing"); exit(2) }
        let config = EASConfiguration(host: host, account: user, password: pass,
                                      domain: v["EAS_DOMAIN"] ?? "", deviceID: deviceID)
        let client = EASClient(configuration: config, transport: URLSessionTransport(configuration: config))
        for id in ["13", "4", "18"] {
            do {
                let b = try await client.sync(collectionID: id, syncKey: "0")
                print("INBOX collection \(id) bootstrap key=\(b.syncKey)")
                let w = try await client.sync(collectionID: id, syncKey: b.syncKey)
                print("INBOX collection \(id) window added=\(w.added.count) key=\(w.syncKey)")
            } catch {
                print("INBOX collection \(id) FAILED \(String(describing: error))")
            }
        }
    }
}
