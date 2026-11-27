// Verify: read-only check that no "uumail" smoke draft was left in the server Drafts folder.
import EASClient
import Foundation

@main
struct Verify {
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
        guard let host = values["EAS_HOST"], let user = values["EAS_USER"],
              let pass = values["EAS_PASS"], let deviceID = values["EAS_DEVICE_ID"] else {
            print("VERIFY config missing"); exit(2)
        }
        let config = EASConfiguration(host: host, account: user, password: pass,
                                      domain: values["EAS_DOMAIN"] ?? "", deviceID: deviceID)
        let client = EASClient(configuration: config, transport: URLSessionTransport(configuration: config))
        do {
            let bootstrap = try await client.sync(collectionID: "4", syncKey: "0")
            let window = try await client.sync(collectionID: "4", syncKey: bootstrap.syncKey)
            let markers = window.added.filter { ($0.subject ?? "").contains("uumail") }
            print("VERIFY drafts in window: \(window.added.count), uumail leftovers: \(markers.count)")
            for message in markers {
                print("VERIFY leftover: \(message.subject ?? "?") serverID=\(message.serverID)")
            }
        } catch {
            print("VERIFY ERROR \(String(describing: error))")
            exit(1)
        }
    }
}
