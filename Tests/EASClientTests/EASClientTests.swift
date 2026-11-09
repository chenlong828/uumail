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

@Suite("EASClient sync")
struct EASSyncTests {
    private func syncResponse(
        status: String,
        syncKey: String,
        adds: [EASMessage],
        moreAvailable: Bool = false
    ) -> Data {
        var commands: [WBXMLElement] = []
        for message in adds {
            var fields: [WBXMLElement] = []
            if let subject = message.subject { fields.append(.text("Subject", subject)) }
            if let from = message.from { fields.append(.text("From", from)) }
            if let date = message.dateReceived { fields.append(.text("DateReceived", date)) }
            if let read = message.isRead { fields.append(.text("Read", read ? "1" : "0")) }
            if let preview = message.bodyPreview {
                fields.append(.children("Body", [.text("Data", preview)]))
            }
            commands.append(.children("Add", [
                .text("ServerId", message.serverID),
                .children("ApplicationData", fields),
            ]))
        }
        var collection: [WBXMLElement] = [
            .text("SyncKey", syncKey),
            .text("CollectionId", "13"),
            .text("Status", status),
        ]
        if !commands.isEmpty {
            collection.append(.children("Commands", commands))
        }
        var sync: [WBXMLElement] = [.children("Collections", [.children("Collection", collection)])]
        if moreAvailable {
            sync.append(.empty("MoreAvailable"))
        }
        return try! WBXMLCodec.standard().encode(.children("Sync", sync))
    }

    @Test("sync parses envelopes and the new key")
    func parsesEnvelopes() async throws {
        let stub = StubTransport(responses: [
            EASHTTPResponse(status: 200, headers: [:], body: syncResponse(
                status: "1",
                syncKey: "43",
                adds: [
                    EASMessage(
                        serverID: "123",
                        subject: "Hello",
                        from: "a@b.c",
                        to: "me@x.y",
                        dateReceived: "2026-11-08T05:11:18.000Z",
                        isRead: false,
                        importance: 1,
                        bodyPreview: "preview text"
                    )
                ]
            ))
        ])
        let client = EASClient(configuration: makeConfiguration(), transport: stub, policyKey: "1")
        let result = try await client.sync(collectionID: "13", syncKey: "42", window: 25)

        #expect(result.syncKey == "43")
        #expect(result.moreAvailable == false)
        #expect(result.added.count == 1)
        let message = try #require(result.added.first)
        #expect(message.serverID == "123")
        #expect(message.subject == "Hello")
        #expect(message.isRead == false)
        #expect(message.bodyPreview == "preview text")

        let request = try #require(await stub.recorded.first?.request)
        let body = try #require(request.body)
        let document = try WBXMLCodec.standard().decode(body)
        let collection = try #require(document.path("Sync", "Collections", "Collection"))
        #expect(collection.child("SyncKey")?.stringValue() == "42")
        #expect(collection.child("CollectionId")?.stringValue() == "13")
        #expect(document.child("Sync")?.child("SyncKey") == nil, "a top-level SyncKey makes Exchange answer Status=4")
        #expect(collection.child("Class") == nil)
    }

    @Test("MoreAvailable is reported so the caller keeps pulling")
    func moreAvailable() async throws {
        let stub = StubTransport(responses: [
            EASHTTPResponse(status: 200, headers: [:], body: syncResponse(
                status: "1", syncKey: "44", adds: [], moreAvailable: true
            ))
        ])
        let client = EASClient(configuration: makeConfiguration(), transport: stub, policyKey: "1")
        let result = try await client.sync(collectionID: "13")
        #expect(result.moreAvailable == true)
        #expect(result.syncKey == "44")
    }

    @Test("Sync status 3 and 4 mean the key is invalid")
    func invalidKey() async {
        for status in ["3", "4"] {
            let stub = StubTransport(responses: [
                EASHTTPResponse(status: 200, headers: [:], body: syncResponse(
                    status: status, syncKey: "0", adds: []
                ))
            ])
            let client = EASClient(configuration: makeConfiguration(), transport: stub, policyKey: "1")
            await #expect(throws: EASError.syncKeyInvalid) {
                _ = try await client.sync(collectionID: "13", syncKey: "42")
            }
        }
    }
}

@Suite("EASClient body fetch")
struct EASBodyTests {
    private func bodyResponse(html: String) -> Data {
        let codec = try! WBXMLCodec.standard()
        return try! codec.encode(.children("ItemOperations", [
            .text("Status", "1"),
            .children("Response", [
                .children("Fetch", [
                    .text("Status", "1"),
                    .text("CollectionId", "13"),
                    .text("ServerId", "101"),
                    .children("Properties", [
                        .children("Body", [
                            .text("Type", "2"),
                            .text("Data", html),
                        ]),
                    ]),
                ]),
            ]),
        ]))
    }

    @Test("fetchBody asks ItemOperations for HTML and returns the payload")
    func fetchesBody() async throws {
        let stub = StubTransport(responses: [
            EASHTTPResponse(status: 200, headers: [:], body: bodyResponse(html: "<html>hello</html>"))
        ])
        let client = EASClient(configuration: makeConfiguration(), transport: stub, policyKey: "1")
        let html = try await client.fetchBody(collectionID: "13", serverID: "101")

        #expect(html == "<html>hello</html>")
        let request = try #require(await stub.recorded.first?.request)
        let document = try WBXMLCodec.standard().decode(try #require(request.body))
        #expect(document.path("ItemOperations", "Fetch", "Store")?.stringValue() == "Mailbox")
        #expect(document.path("ItemOperations", "Fetch", "CollectionId")?.stringValue() == "13")
        #expect(document.path("ItemOperations", "Fetch", "ServerId")?.stringValue() == "101")
        #expect(document.path("ItemOperations", "Fetch", "Options", "BodyPreference", "Type")?.stringValue() == "2")
        #expect(document.path("ItemOperations", "Fetch", "Options", "BodyPreference", "TruncationSize")?.stringValue() == "20000")
    }

    @Test("ItemOperations status 2 is a failure, not an empty body")
    func statusFailure() async {
        let codec = try! WBXMLCodec.standard()
        let failure = try! codec.encode(.children("ItemOperations", [.text("Status", "2")]))
        let stub = StubTransport(responses: [
            EASHTTPResponse(status: 200, headers: [:], body: failure)
        ])
        let client = EASClient(configuration: makeConfiguration(), transport: stub, policyKey: "1")
        await #expect(throws: EASError.permanent(status: 200, detail: "ItemOperations status=2")) {
            _ = try await client.fetchBody(collectionID: "13", serverID: "101")
        }
    }
}

@Suite("EASClient attachments")
struct EASAttachmentTests {
    @Test("Sync parses attachment metadata into the envelope")
    func parsesAttachmentMetadata() async throws {
        let codec = try! WBXMLCodec.standard()
        let response = try! codec.encode(.children("Sync", [
            .children("Collections", [
                .children("Collection", [
                    .text("SyncKey", "2"),
                    .text("CollectionId", "13"),
                    .text("Status", "1"),
                    .children("Commands", [
                        .children("Add", [
                            .text("ServerId", "101"),
                            .children("ApplicationData", [
                                .text("Subject", "with file"),
                                .children("Attachments", [
                                    .children("Attachment", [
                                        .text("DisplayName", "report.pdf"),
                                        .text("FileReference", "ref-1"),
                                        .text("EstimatedDataSize", "72084"),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ]))
        let stub = StubTransport(responses: [EASHTTPResponse(status: 200, headers: [:], body: response)])
        let client = EASClient(configuration: makeConfiguration(), transport: stub, policyKey: "1")
        let result = try await client.sync(collectionID: "13")
        let attachment = try #require(result.added.first?.attachments.first)
        #expect(attachment.displayName == "report.pdf")
        #expect(attachment.fileReference == "ref-1")
        #expect(attachment.size == 72084)
    }

    @Test("fetchAttachment decodes the base64 payload")
    func fetchesAttachment() async throws {
        let payload = Data([0x25, 0x50, 0x44, 0x46]) // %PDF
        let codec = try! WBXMLCodec.standard()
        let response = try! codec.encode(.children("ItemOperations", [
            .text("Status", "1"),
            .text("Data", payload.base64EncodedString()),
        ]))
        let stub = StubTransport(responses: [EASHTTPResponse(status: 200, headers: [:], body: response)])
        let client = EASClient(configuration: makeConfiguration(), transport: stub, policyKey: "1")
        let data = try await client.fetchAttachment(fileReference: "ref-1")
        #expect(data == payload)

        let request = try #require(await stub.recorded.first?.request)
        let doc = try codec.decode(try #require(request.body))
        #expect(doc.path("ItemOperations", "Fetch", "Store")?.stringValue() == "Mailbox")
        #expect(doc.path("ItemOperations", "Fetch", "FileReference")?.stringValue() == "ref-1")
    }
}

@Suite("EASClient send")
struct EASSendTests {
    @Test("SendMail succeeds on 200 with a zero-byte body")
    func sendsMail() async throws {
        let stub = StubTransport(responses: [EASHTTPResponse(status: 200, headers: [:], body: Data())])
        let client = EASClient(configuration: makeConfiguration(), transport: stub, policyKey: "1")
        let mime = Data("From: a@b.c\r\nSubject: hi\r\n\r\nbody".utf8)
        let clientID = try await client.send(mime: mime)

        #expect(clientID.count == 36)
        let request = try #require(await stub.recorded.first?.request)
        let doc = try WBXMLCodec.standard().decode(try #require(request.body))
        #expect(doc.path("SendMail", "ClientId")?.stringValue() == clientID)
        #expect(doc.path("SendMail", "SaveInSentItems") != nil)
        #expect(doc.path("SendMail", "Mime")?.opaque == mime)
    }

    @Test("a non-empty 200 is still treated as success for SendMail")
    func nonEmptyBodyIsSuccess() async throws {
        let codec = try! WBXMLCodec.standard()
        let errorBody = try! codec.encode(.children("SendMail", [.text("Status", "1")]))
        let stub = StubTransport(responses: [EASHTTPResponse(status: 200, headers: [:], body: errorBody)])
        let client = EASClient(configuration: makeConfiguration(), transport: stub, policyKey: "1")
        _ = try await client.send(mime: Data("x".utf8))
    }

    @Test("401 on SendMail is an auth failure")
    func authFailure() async {
        let stub = StubTransport(responses: [EASHTTPResponse(status: 401, headers: [:], body: Data())])
        let client = EASClient(configuration: makeConfiguration(), transport: stub, policyKey: "1")
        await #expect(throws: EASError.authFailed) {
            _ = try await client.send(mime: Data("x".utf8))
        }
    }
}
