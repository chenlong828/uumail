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

/// Replays a real Sync envelope; the fields the adapter maps come from
/// `ApplicationData`, not from domain values.
private func syncResponse(added: [EASMessage], changed: [EASMessage] = []) -> Data {
    func command(_ kind: String, _ message: EASMessage) -> WBXMLElement {
        var fields: [WBXMLElement] = []
        if let subject = message.subject { fields.append(.text("Subject", subject)) }
        if let from = message.from { fields.append(.text("From", from)) }
        if let to = message.to { fields.append(.text("To", to)) }
        if let cc = message.cc { fields.append(.text("Cc", cc)) }
        if let date = message.dateReceived { fields.append(.text("DateReceived", date)) }
        if let read = message.isRead { fields.append(.text("Read", read ? "1" : "0")) }
        return .children(kind, [
            .text("ServerId", message.serverID),
            .children("ApplicationData", fields),
        ])
    }

    let commands = added.map { command("Add", $0) } + changed.map { command("Change", $0) }
    return try! WBXMLCodec.standard().encode(.children("Sync", [
        .children("Collections", [
            .children("Collection", [
                .text("SyncKey", "43"),
                .text("CollectionId", "13"),
                .text("Status", "1"),
                .children("Commands", commands),
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

    @Test("Sync envelopes carry Cc into the domain message")
    func mapsCcFromSyncEnvelopes() async throws {
        let stub = StubTransport(responses: [
            EASHTTPResponse(status: 200, headers: [:], body: syncResponse(
                added: [
                    EASMessage(
                        serverID: "123",
                        subject: "Hello",
                        from: "a@b.c",
                        to: "me@x.y",
                        cc: "c@x.y; d@x.z"
                    )
                ],
                changed: [EASMessage(serverID: "124", cc: "e@x.y")]
            ))
        ])
        let adapter = EASAdapter(client: EASClient(configuration: configuration(), transport: stub, policyKey: "1"))

        let delta = try await adapter.fetchMessages(
            collectionID: "13", syncKey: "42", window: 25, filterType: 0
        )

        let added = try #require(delta.added.first)
        #expect(added.cc == "c@x.y; d@x.z")
        #expect(added.recipients == "me@x.y")
        let changed = try #require(delta.changed.first)
        #expect(changed.cc == "e@x.y")
    }

    @Test("messages without Cc keep a nil domain cc")
    func absentCcStaysNil() async throws {
        let stub = StubTransport(responses: [
            EASHTTPResponse(status: 200, headers: [:], body: syncResponse(
                added: [
                    EASMessage(serverID: "1"),
                    EASMessage(serverID: "2", cc: "   "),
                ]
            ))
        ])
        let adapter = EASAdapter(client: EASClient(configuration: configuration(), transport: stub, policyKey: "1"))

        let delta = try await adapter.fetchMessages(
            collectionID: "13", syncKey: "42", window: 25, filterType: 0
        )

        #expect(delta.added.count == 2)
        #expect(delta.added[0].cc == nil)
        #expect(delta.added[1].cc == nil, "the protocol layer normalizes blank Cc to nil")
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
