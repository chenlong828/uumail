import Foundation
import Testing

@testable import EASClient

actor StubTransport: EASHTTPTransport {
    struct Recorded {
        let request: EASHTTPRequest
        let query: [String: String]
    }

    private(set) var recorded: [Recorded] = []
    private var responses: [EASHTTPResponse]
    private let delayNanoseconds: UInt64

    init(responses: [EASHTTPResponse], delaySeconds: TimeInterval = 0) {
        self.responses = responses
        self.delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)
    }

    func send(_ request: EASHTTPRequest) async throws -> EASHTTPResponse {
        let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name] = item.value
        }
        recorded.append(Recorded(request: request, query: query))
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        guard !responses.isEmpty else {
            throw EASError.transient(reason: "stub exhausted")
        }
        return responses.removeFirst()
    }
}

func makeConfiguration() -> EASConfiguration {
    EASConfiguration(
        host: "mail.example.test",
        account: "jdoe",
        password: "secret",
        domain: "CORP",
        deviceID: "DEVICEID0000000000000000000001"
    )
}

/// Builds a FolderSync WBXML response so the tests exercise the real decoder.
func folderSyncResponse(status: String, syncKey: String, folders: [(String, String, Int)]) -> Data {
    var changes: [WBXMLElement] = []
    for (id, name, type) in folders {
        changes.append(.children("Add", [
            .text("ServerId", id),
            .text("ParentId", "0"),
            .text("DisplayName", name),
            .text("Type", String(type)),
        ]))
    }
    let codec = try! WBXMLCodec.standard()
    return try! codec.encode(.children("FolderSync", [
        .text("SyncKey", syncKey),
        .children("Changes", changes),
        .text("Status", status),
    ]))
}

func provisionResponse(policyKey: String) -> Data {
    let codec = try! WBXMLCodec.standard()
    return try! codec.encode(.children("Provision", [
        .text("Status", "1"),
        .children("Policies", [.children("Policy", [.text("PolicyKey", policyKey)])]),
    ]))
}

@Suite("EASClient transport and commands")
struct EASClientTests {
    @Test("OPTIONS uses the bare URL and reads capabilities")
    func optionsCapabilities() async throws {
        let stub = StubTransport(responses: [
            EASHTTPResponse(
                status: 200,
                headers: [
                    "ms-asprotocolversions": "12.1,14.0,14.1,16.0,16.1",
                    "ms-ascommands": "Sync,FolderSync,SendMail",
                    "set-cookie": "X-BackEndCookie=abc; path=/; secure",
                ],
                body: Data()
            ),
        ])
        let client = EASClient(configuration: makeConfiguration(), transport: stub)
        let caps = try await client.options()
        #expect(caps.protocolVersions == ["12.1", "14.0", "14.1", "16.0", "16.1"])
        #expect(caps.commands == ["Sync", "FolderSync", "SendMail"])

        let request = try #require(await stub.recorded.first?.request)
        #expect(request.method == "OPTIONS")
        #expect(request.url.query == nil, "OPTIONS must hit the bare URL, never ?Cmd=")
        #expect(request.headers["Content-Type"] == nil)
    }

    @Test("folderSync sends the gateway's parameter set and domainless User")
    func folderSyncParameters() async throws {
        let stub = StubTransport(responses: [
            EASHTTPResponse(status: 200, headers: [:], body: provisionResponse(policyKey: "100")),
            EASHTTPResponse(status: 200, headers: [:], body: provisionResponse(policyKey: "200")),
            EASHTTPResponse(
                status: 200,
                headers: [:],
                body: folderSyncResponse(status: "1", syncKey: "5", folders: [("8", "Inbox", 2)])
            ),
        ])
        let client = EASClient(configuration: makeConfiguration(), transport: stub)
        let result = try await client.folderSync()

        #expect(result.syncKey == "5")
        #expect(result.folders == [EASFolder(serverID: "8", parentID: "0", displayName: "Inbox", type: 2)])

        let last = try #require(await stub.recorded.last)
        #expect(last.query["Cmd"] == "FolderSync")
        #expect(last.query["User"] == "jdoe", "User must not carry the domain")
        #expect(last.query["DeviceId"] == "DEVICEID0000000000000000000001")
        #expect(last.query["DeviceType"] == "iPhone")
        #expect(last.request.headers["X-MS-PolicyKey"] == "200")
        #expect(last.request.headers["MS-ASProtocolVersion"] == "16.1")
        let auth = try #require(last.request.headers["Authorization"])
        #expect(auth.hasPrefix("Basic "))
        let decoded = String(
            data: Data(base64Encoded: String(auth.dropFirst("Basic ".count)))!,
            encoding: .utf8
        )
        #expect(decoded == "CORP\\jdoe:secret")
    }

    @Test("zero-byte 200 means the gateway swallowed the request")
    func emptyBodyIsDeviceNotRegistered() async {
        let stub = StubTransport(responses: [EASHTTPResponse(status: 200, headers: [:], body: Data())])
        let client = EASClient(configuration: makeConfiguration(), transport: stub, policyKey: "1")
        await #expect(throws: EASError.deviceNotRegistered) {
            _ = try await client.folderSync()
        }
    }

    @Test("error mapping table")
    func errorMapping() async {
        let cases: [(Int, [String: String], EASError)] = [
            (401, [:], .authFailed),
            (444, [:], .gatewayRejected),
            (449, ["x-ms-aserror": "policy"], .policyRequired(status: 449, message: "policy")),
            (503, ["retry-after": "120"], .throttled(retryAfterSeconds: 120)),
            (503, [:], .throttled(retryAfterSeconds: nil)),
            (500, [:], .transient(reason: "HTTP 500")),
            (404, [:], .permanent(status: 404, detail: nil)),
        ]
        for (status, headers, expected) in cases {
            let stub = StubTransport(responses: [
                EASHTTPResponse(status: status, headers: headers, body: Data())
            ])
            let client = EASClient(configuration: makeConfiguration(), transport: stub, policyKey: "1")
            await #expect(throws: expected) {
                _ = try await client.folderSync()
            }
        }
    }

    @Test("a slow 502 is a wire-format rejection, a fast 502 is an outage")
    func badGatewayClassification() async {
        let slow = StubTransport(
            responses: [EASHTTPResponse(status: 502, headers: [:], body: Data())],
            delaySeconds: 0.2
        )
        let slowClient = EASClient(
            configuration: makeConfiguration(),
            transport: slow,
            policyKey: "1",
            longHangThreshold: 0.1
        )
        do {
            _ = try await slowClient.folderSync()
            Issue.record("expected protocolRejected")
        } catch let error as EASError {
            guard case .protocolRejected(let detail) = error else {
                Issue.record("expected protocolRejected, got \(error)")
                return
            }
            #expect(detail.hasPrefix("502 after"))
        } catch {
            Issue.record("unexpected error \(error)")
        }

        let fast = StubTransport(responses: [EASHTTPResponse(status: 502, headers: [:], body: Data())])
        let fastClient = EASClient(
            configuration: makeConfiguration(),
            transport: fast,
            policyKey: "1",
            longHangThreshold: 10
        )
        await #expect(throws: EASError.transient(reason: "HTTP 502")) {
            _ = try await fastClient.folderSync()
        }
    }

    @Test("Provision runs both steps and keeps the final policy key")
    func provisionTwoSteps() async throws {
        let stub = StubTransport(responses: [
            EASHTTPResponse(status: 200, headers: [:], body: provisionResponse(policyKey: "111")),
            EASHTTPResponse(status: 200, headers: [:], body: provisionResponse(policyKey: "222")),
        ])
        let client = EASClient(configuration: makeConfiguration(), transport: stub)
        let key = try await client.provision()
        #expect(key == "222")
        #expect(await client.currentPolicyKey() == "222")

        let recorded = await stub.recorded
        #expect(recorded.count == 2)
        #expect(recorded[0].query["Cmd"] == "Provision")
        #expect(recorded[0].request.headers["X-MS-PolicyKey"] == nil)
        #expect(recorded[1].query["PolicyKey"] == "111")
        #expect(recorded[1].request.headers["X-MS-PolicyKey"] == "111")
    }

    @Test("FolderSync status other than 1 is a permanent failure")
    func folderSyncStatus() async {
        let stub = StubTransport(responses: [
            EASHTTPResponse(
                status: 200,
                headers: [:],
                body: folderSyncResponse(status: "6", syncKey: "1", folders: [])
            )
        ])
        let client = EASClient(configuration: makeConfiguration(), transport: stub, policyKey: "1")
        await #expect(throws: EASError.permanent(status: 200, detail: "FolderSync status=6")) {
            _ = try await client.folderSync()
        }
    }

    @Test("garbage bodies surface as malformed responses, not silent empty results")
    func malformedBody() async {
        let stub = StubTransport(responses: [
            EASHTTPResponse(status: 200, headers: [:], body: Data([0xFF, 0x00]))
        ])
        let client = EASClient(configuration: makeConfiguration(), transport: stub, policyKey: "1")
        await #expect(throws: EASError.self) {
            _ = try await client.folderSync()
        }
    }
}
