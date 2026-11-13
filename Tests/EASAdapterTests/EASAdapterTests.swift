import EASClient
import Foundation
import MailDomain
import Testing

@testable import EASAdapter

actor StubTransport: EASHTTPTransport {
    private var responses: [EASHTTPResponse]

    init(responses: [EASHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: EASHTTPRequest) async throws -> EASHTTPResponse {
        guard !responses.isEmpty else {
            throw EASError.transient(reason: "stub exhausted")
        }
        return responses.removeFirst()
    }
}

private func configuration() -> EASConfiguration {
    EASConfiguration(
        host: "mail.example.test",
        account: "jdoe",
        password: "secret",
        domain: "CORP",
        deviceID: "DEVICEID0000000000000000000001"
    )
}

private func bodyResponse(text: String, type: String = "2", truncated: Bool = false) -> Data {
    let codec = try! WBXMLCodec.standard()
    var body: [WBXMLElement] = [.text("Type", type)]
    if truncated {
        body.append(.text("Truncated", "1"))
    }
    body.append(.text("Data", text))
    return try! codec.encode(.children("ItemOperations", [
        .text("Status", "1"),
        .children("Response", [
            .children("Fetch", [
                .text("Status", "1"),
                .text("CollectionId", "13"),
                .text("ServerId", "101"),
                .children("Properties", [
                    .children("Body", body),
                ]),
            ]),
        ]),
    ]))
}

@Suite("EASAdapter gateway")
struct EASAdapterTests {
    @Test("HTML bodies keep their payload and flags")
    func htmlBodyPassesThrough() async throws {
        let stub = StubTransport(responses: [
            EASHTTPResponse(status: 200, headers: [:], body: bodyResponse(text: "<p>hi</p>"))
        ])
        let adapter = EASAdapter(client: EASClient(configuration: configuration(), transport: stub, policyKey: "1"))

        let body = try await adapter.fetchBody(collectionID: "13", serverID: "101")
        #expect(body.text == "<p>hi</p>")
        #expect(body.isHTML)
        #expect(!body.isTruncated)
    }

    @Test("a server-side truncation stays visible to the scene")
    func truncatedBodyStaysFlagged() async throws {
        let stub = StubTransport(responses: [
            EASHTTPResponse(status: 200, headers: [:], body: bodyResponse(text: "<p>cut</p>", truncated: true)),
            EASHTTPResponse(status: 200, headers: [:], body: bodyResponse(text: "<p>cut</p>", truncated: true)),
        ])
        let adapter = EASAdapter(client: EASClient(configuration: configuration(), transport: stub, policyKey: "1"))

        let body = try await adapter.fetchBody(collectionID: "13", serverID: "101")
        #expect(body.isTruncated, "the second request is still truncated, so the flag must survive")
    }

    @Test("plain text answers are marked so the scene can convert them")
    func plainTextIsMarked() async throws {
        let stub = StubTransport(responses: [
            EASHTTPResponse(status: 200, headers: [:], body: bodyResponse(text: "line1\nline2", type: "1"))
        ])
        let adapter = EASAdapter(client: EASClient(configuration: configuration(), transport: stub, policyKey: "1"))

        let body = try await adapter.fetchBody(collectionID: "13", serverID: "101")
        #expect(!body.isHTML)
        #expect(body.text == "line1\nline2")
        #expect(!body.isTruncated)
    }

    @Test("401 becomes authFailed in the domain catalog")
    func mapsAuthFailure() async {
        let stub = StubTransport(responses: [
            EASHTTPResponse(status: 401, headers: [:], body: Data())
        ])
        let adapter = EASAdapter(client: EASClient(configuration: configuration(), transport: stub, policyKey: "1"))

        await #expect(throws: MailError.authFailed) {
            _ = try await adapter.probe()
        }
    }
}
