import Foundation
import Testing

@testable import EASClient

/// One Sync write response: collection status 1, the next key and (for Add) the server id.
private func draftWriteResponse(syncKey: String, serverID: String?) -> Data {
    var responses: [WBXMLElement] = []
    if let serverID {
        responses.append(.children("Add", [
            .text("ClientId", "cid"),
            .text("ServerId", serverID),
            .text("Status", "1"),
        ]))
    }
    let codec = try! WBXMLCodec.standard()
    return try! codec.encode(.children("Sync", [
        .children("Collections", [
            .children("Collection", [
                .text("SyncKey", syncKey),
                .text("Status", "1"),
                .children("Responses", responses),
            ]),
        ]),
    ]))
}

private func makeClient(_ responses: [Data]) -> (EASClient, StubTransport) {
    let stub = StubTransport(responses: responses.map {
        EASHTTPResponse(status: 200, headers: [:], body: $0)
    })
    return (EASClient(configuration: makeConfiguration(), transport: stub, policyKey: "1"), stub)
}

@Suite("EAS drafts")
struct EASDraftWriteTests {
    @Test("createDraft sends a Sync Add with the draft fields and reads ServerId")
    func createDraft() async throws {
        let (client, stub) = makeClient([draftWriteResponse(syncKey: "9", serverID: "4:1")])

        let result = try await client.createDraft(
            EASDraft(to: "a@b.c", cc: "c@d.e", subject: "hi", bodyHTML: "<p>x</p>"),
            collectionID: "4", syncKey: "8", clientID: "outbox-1"
        )

        #expect(result.serverID == "4:1")
        #expect(result.syncKey == "9")
        let request = try #require(await stub.recorded.last?.request)
        let body = try #require(request.body)
        let document = try WBXMLCodec.standard().decode(body)
        let collection = try #require(document.path("Sync", "Collections", "Collection"))
        #expect(collection.child("SyncKey")?.stringValue() == "8")
        #expect(collection.child("CollectionId")?.stringValue() == "4")
        let add = try #require(collection.path("Commands", "Add"))
        #expect(add.child("ClientId")?.stringValue() == "outbox-1")
        #expect(add.path("ApplicationData", "To")?.stringValue() == "a@b.c")
        #expect(add.path("ApplicationData", "Cc")?.stringValue() == "c@d.e")
        #expect(add.path("ApplicationData", "Subject")?.stringValue() == "hi")
        #expect(add.path("ApplicationData", "Body", "Type")?.stringValue() == "2")
        #expect(add.path("ApplicationData", "Body", "Data")?.stringValue() == "<p>x</p>")
    }

    @Test("updateDraft sends a Sync Change addressed by ServerId")
    func updateDraft() async throws {
        let (client, stub) = makeClient([draftWriteResponse(syncKey: "10", serverID: nil)])

        let result = try await client.updateDraft(
            serverID: "4:7",
            draft: EASDraft(to: "a@b.c", cc: nil, subject: "new", bodyHTML: "<p>y</p>"),
            collectionID: "4", syncKey: "9"
        )

        #expect(result.serverID == nil)
        #expect(result.syncKey == "10")
        let request = try #require(await stub.recorded.last?.request)
        let body = try #require(request.body)
        let document = try WBXMLCodec.standard().decode(body)
        let change = try #require(document.path("Sync", "Collections", "Collection", "Commands", "Change"))
        #expect(change.child("ServerId")?.stringValue() == "4:7")
        #expect(change.path("ApplicationData", "Subject")?.stringValue() == "new")
    }

    @Test("deleteDraft sends a Sync Delete")
    func deleteDraft() async throws {
        let (client, stub) = makeClient([draftWriteResponse(syncKey: "11", serverID: nil)])

        let result = try await client.deleteDraft(
            serverID: "4:8", collectionID: "4", syncKey: "10"
        )

        #expect(result.syncKey == "11")
        let request = try #require(await stub.recorded.last?.request)
        let body = try #require(request.body)
        let document = try WBXMLCodec.standard().decode(body)
        let delete = try #require(document.path("Sync", "Collections", "Collection", "Commands", "Delete"))
        #expect(delete.child("ServerId")?.stringValue() == "4:8")
    }
}
