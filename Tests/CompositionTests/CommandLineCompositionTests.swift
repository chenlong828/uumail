import Foundation
import MailDomain
import MailStore
import Testing

@testable import Composition

/// The CLI assembly uses the same scenes as the app: an empty database goes through the
/// setup scene once, and an existing account row is reused without a probe.
@Suite("Command line composition")
struct CommandLineCompositionTests {
    @Test("an empty database is bootstrapped through the setup scene, then reused")
    func bootstrapsAndReusesAccount() async throws {
        let directory = makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("cli.sqlite").path
        let configuration = makeAssemblyConfiguration()
        let gateway = AssemblyGateway(folders: makeFolderListing(), deltas: makeSyncDeltas())

        let composition = try await CommandLineComposition.make(
            databasePath: path,
            configuration: configuration,
            gatewayFactory: makeGatewayFactory(gateway)
        )

        #expect(composition.configuration == configuration)
        let accounts = try composition.store.accounts()
        #expect(accounts.count == 1)
        #expect(accounts.first == composition.account)
        let calls = await gateway.calls
        #expect(calls.contains(.probe))
        #expect(calls.contains(.provision))
        #expect(calls.contains(.folders(syncKey: "0")))
        #expect(try composition.store.folders(account: composition.account).map(\.serverID) == ["13"])

        // A second assembly for the same database reuses the row without probing again.
        let second = try await CommandLineComposition.make(
            databasePath: path,
            configuration: configuration,
            gatewayFactory: makeGatewayFactory(gateway)
        )
        #expect(second.account == composition.account)
        let probeCalls = await gateway.probeCalls
        #expect(probeCalls == 1)
    }
}
