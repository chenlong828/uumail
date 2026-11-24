import EASClient
import Foundation
import MailDomain
import Testing
import MeetingDomain

@testable import EASAdapter

actor StubTransport: EASHTTPTransport {
    private var responses: [EASHTTPResponse]
    private(set) var recorded: [EASHTTPRequest] = []

    init(responses: [EASHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: EASHTTPRequest) async throws -> EASHTTPResponse {
        recorded.append(request)
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

    @Test("markRead passes the write delta through without trimming it")
    func markReadPassesDeltaThrough() async throws {
        let stub = StubTransport(responses: [
            EASHTTPResponse(status: 200, headers: [:], body: syncResponse(
                added: [EASMessage(serverID: "9", subject: "new")],
                changed: [EASMessage(serverID: "123", isRead: true)]
            ))
        ])
        let adapter = EASAdapter(client: EASClient(configuration: configuration(), transport: stub, policyKey: "1"))

        let delta = try await adapter.markRead(collectionID: "13", serverID: "123", syncKey: "42")

        #expect(delta.syncKey == "43")
        #expect(delta.added.map(\.serverID) == ["9"])
        #expect(delta.changed.map(\.serverID) == ["123"])
        #expect(delta.changed.first?.isRead == true)

        let request = try #require(await stub.recorded.first)
        let document = try WBXMLCodec.standard().decode(try #require(request.body))
        #expect(document.path("Sync", "Collections", "Collection", "Commands", "Change", "ServerId")?.stringValue() == "123")
    }

    @Test("delete passes removed ids through and maps a write 401")
    func deletePassesDeltaAndMaps401() async throws {
        let codec = try! WBXMLCodec.standard()
        let deleteResponse = try! codec.encode(.children("Sync", [
            .children("Collections", [
                .children("Collection", [
                    .text("SyncKey", "43"),
                    .text("CollectionId", "13"),
                    .text("Status", "1"),
                    .children("Commands", [
                        .children("Delete", [.text("ServerId", "123")]),
                    ]),
                ]),
            ]),
        ]))
        let stub = StubTransport(responses: [
            EASHTTPResponse(status: 200, headers: [:], body: deleteResponse)
        ])
        let adapter = EASAdapter(client: EASClient(configuration: configuration(), transport: stub, policyKey: "1"))

        let delta = try await adapter.delete(collectionID: "13", serverID: "123", syncKey: "42")
        #expect(delta.removedServerIDs == ["123"])
        #expect(delta.syncKey == "43")

        let unauthorized = StubTransport(responses: [
            EASHTTPResponse(status: 401, headers: [:], body: Data())
        ])
        let rejected = EASAdapter(client: EASClient(configuration: configuration(), transport: unauthorized, policyKey: "1"))
        await #expect(throws: MailError.deviceNotRegistered) {
            _ = try await rejected.delete(collectionID: "13", serverID: "123", syncKey: "42")
        }
    }

    @Test("write failures map to the domain catalog")
    func mapsWriteFailures() async {
        let staleKey = try! WBXMLCodec.standard().encode(.children("Sync", [
            .children("Collections", [
                .children("Collection", [
                    .text("SyncKey", "0"), .text("CollectionId", "13"), .text("Status", "3"),
                ]),
            ]),
        ]))
        let stale = StubTransport(responses: [
            EASHTTPResponse(status: 200, headers: [:], body: staleKey)
        ])
        let staleAdapter = EASAdapter(client: EASClient(configuration: configuration(), transport: stale, policyKey: "1"))
        await #expect(throws: MailError.syncKeyInvalid) {
            _ = try await staleAdapter.markRead(collectionID: "13", serverID: "1", syncKey: "42")
        }

        let throttled = StubTransport(responses: [
            EASHTTPResponse(status: 503, headers: ["retry-after": "30"], body: Data())
        ])
        let throttledAdapter = EASAdapter(client: EASClient(configuration: configuration(), transport: throttled, policyKey: "1"))
        await #expect(throws: MailError.throttled(seconds: 30)) {
            _ = try await throttledAdapter.delete(collectionID: "13", serverID: "1", syncKey: "42")
        }

        let offline = StubTransport(responses: [
            EASHTTPResponse(status: 500, headers: [:], body: Data())
        ])
        let offlineAdapter = EASAdapter(client: EASClient(configuration: configuration(), transport: offline, policyKey: "1"))
        await #expect(throws: MailError.offline) {
            _ = try await offlineAdapter.markRead(collectionID: "13", serverID: "1", syncKey: "42")
        }
    }
}

@Suite("EASAdapter meeting requests")
struct EASAdapterMeetingTests {
    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    private func easMessage(
        messageClass: String = "IPM.Schedule.Meeting.Request",
        meeting: EASMeeting? = EASMeeting(
            uid: "u-1",
            start: ISO8601DateFormatter().date(from: "2026-11-19T01:30:00Z"),
            end: ISO8601DateFormatter().date(from: "2026-11-19T04:00:00Z"),
            dtstamp: ISO8601DateFormatter().date(from: "2026-11-13T09:54:53Z"),
            location: "C4519",
            organizer: "\"王权英\" <wangqy@hundsun.com>",
            reminderMinutes: 900,
            responseRequested: true,
            busyStatus: 2,
            messageType: 2,
            instanceType: 1,
            timeZone: EASMeetingTimeZone(name: "China Standard Time", biasMinutes: -480),
            recurrence: EASRecurrence(type: 1, interval: 1, daysOfWeek: 2, firstDayOfWeek: 1)
        )
    ) -> EASMessage {
        EASMessage(
            serverID: "m-1",
            subject: "【会议预告】",
            from: "wangqy@hundsun.com",
            messageClass: messageClass,
            meeting: meeting
        )
    }

    @Test("a meeting request maps onto the domain invite")
    func mapsRequest() throws {
        let message = easMessage()
        let meeting = try #require(EASAdapter.meeting(message))
        #expect(meeting.uid == "u-1")
        #expect(meeting.location == "C4519")
        #expect(meeting.organizer == "\"王权英\" <wangqy@hundsun.com>")
        #expect(meeting.reminderMinutes == 900)
        #expect(meeting.responseRequested)
        #expect(meeting.messageType == .update)
        #expect(meeting.isCancelled == false)
        #expect(meeting.timeZone?.offsetSeconds == 28800)
        #expect(meeting.timeZone?.name == "China Standard Time")
        let rule = try #require(meeting.recurrence)
        #expect(rule.frequency == .weekly)
        #expect(rule.interval == 1)
        #expect(rule.weekdays == [.monday])
        #expect(rule.firstDayOfWeek == .monday)
    }

    @Test("a cancelled request keeps the meeting but flags it")
    func mapsCancellation() throws {
        let meeting = EASAdapter.meeting(easMessage(messageClass: "IPM.Schedule.Meeting.Canceled"))
        #expect(try #require(meeting).isCancelled)
    }

    @Test("a plain note never produces a meeting")
    func plainNoteHasNoMeeting() {
        #expect(EASAdapter.meeting(easMessage(messageClass: "IPM.Note")) == nil)
    }

    @Test("a request without times degrades to plain mail")
    func missingTimesDegrade() {
        var incomplete = easMessage()
        incomplete.meeting?.start = nil
        #expect(EASAdapter.meeting(incomplete) == nil)
    }

    @Test("an exception instance does not carry the series rule")
    func exceptionDropsRecurrence() {
        var exception = easMessage()
        exception.meeting?.instanceType = 3
        #expect(EASAdapter.meeting(exception)?.recurrence == nil)
    }
}
