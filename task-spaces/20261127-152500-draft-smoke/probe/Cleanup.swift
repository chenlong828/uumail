// Cleanup: delete the smoke draft left on the server and report the exact protocol error.
import EASAdapter
import EASClient
import Foundation

func parseEnv(_ path: String) -> [String: String] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
    var values: [String: String] = [:]
    for line in text.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { continue }
        var v = String(t[t.index(after: eq)...])
        if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
        values[String(t[..<eq])] = v
    }
    return values
}

@main
struct Cleanup {
    static func main() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let values = parseEnv(home + "/.uumail.env")
        guard let host = values["EAS_HOST"], let user = values["EAS_USER"],
              let pass = values["EAS_PASS"], let deviceID = values["EAS_DEVICE_ID"] else {
            print("CLEANUP config missing"); exit(2)
        }
        let config = EASConfiguration(
            host: host, account: user, password: pass,
            domain: values["EAS_DOMAIN"] ?? "", deviceID: deviceID, protocolVersion: "16.1"
        )
        let client = EASClient(configuration: config, transport: URLSessionTransport(configuration: config))
        let serverID = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "_YPprqSaOkKgdRfWHADCtgAAAAABD_2D6a6kmjpCoHUX1hwAwrYAAk8CLmU1"
        do {
            let bootstrap = try await client.sync(collectionID: "4", syncKey: "0")
            print("CLEANUP bootstrap key=\(bootstrap.syncKey) added=\(bootstrap.added.count)")
            do {
                let result = try await client.deleteDraft(
                    serverID: serverID, collectionID: "4", syncKey: bootstrap.syncKey
                )
                print("CLEANUP deleteDraft ok newKey=\(result.syncKey)")
            } catch {
                print("CLEANUP deleteDraft error: \(String(describing: error))")
            }
            do {
                _ = try await client.fetchBody(collectionID: "4", serverID: serverID)
                print("CLEANUP verify: server copy STILL present")
            } catch {
                print("CLEANUP verify: server copy gone (\(String(describing: error)))")
            }
        } catch {
            print("CLEANUP unexpected: \(String(describing: error))")
            exit(1)
        }
    }
}
