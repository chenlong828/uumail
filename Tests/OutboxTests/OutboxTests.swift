import Foundation
import MailDomain
import MailStore
import Outbox
import Testing

@Suite("Outbox delivery")
struct OutboxDeliveryTests {
    private func fixture(
        gateway: FakeGateway? = nil,
        clock: TestClock? = nil,
        sendTimeout: Duration = .seconds(90)
    ) throws -> (store: MailStore, account: AccountID, gateway: FakeGateway, clock: TestClock, outbox: Outbox) {
        let (store, account) = try seededStore()
        let gateway = gateway ?? FakeGateway()
        let clock = clock ?? TestClock()
        let outbox = Outbox(store: store, gateway: gateway, clock: clock, sendTimeout: sendTimeout)
        return (store, account, gateway, clock, outbox)
    }

    @Test("enqueue only writes a queued local row and returns immediately")
    func enqueueIsLocal() async throws {
        let (_, account, gateway, _, outbox) = try fixture()

        let id = try await outbox.enqueue(makeDraft(), account: account)

        let state = try await outbox.state(of: id, account: account)
        #expect(state == .queued)
        let pending = try await outbox.pending(account: account)
        #expect(pending.map(\.id) == [id.raw])
        #expect(pending.first?.attempts == 0)
        #expect(pending.first?.nextAttemptAt == nil)
        #expect(await gateway.attempts == 0, "enqueue must not touch the network")
    }

    @Test("flushOnce sends once with ClientId = outboxID, then removes the row")
    func deliversOnce() async throws {
        let (_, account, gateway, _, outbox) = try fixture()
        let draft = MailDraft(
            to: "a@b.c", cc: "c@d.e", subject: "hi", body: "text",
            inReplyTo: "<id@x>", references: "<id@x>"
        )
        let id = try await outbox.enqueue(draft, account: account)

        let outcome = await outbox.flushOnce(account: account)

        #expect(outcome == .sent(id))
        let state = try await outbox.state(of: id, account: account)
        #expect(state == nil)
        let stillPending = try await outbox.pending(account: account)
        #expect(stillPending.isEmpty)
        #expect(await gateway.attempts == 1)
        #expect(await gateway.clientIDs == [id.raw], "ClientId doubles as the idempotency key")

        let sent = await gateway.sentMIME
        #expect(sent.count == 1)
        let mime = String(decoding: sent[0], as: UTF8.self)
        // From comes from the stored account address; Message-ID uses the stored host.
        #expect(mime.contains("From: jdoe@corp.test"))
        #expect(mime.contains("To: a@b.c"))
        #expect(mime.contains("Cc: c@d.e"))
        #expect(mime.contains("@mail.corp.test>"))
    }

    @Test("enqueue keeps bodyHTML and delivery sends a multipart alternative")
    func deliversHTML() async throws {
        let (store, account, gateway, _, outbox) = try fixture()
        let html = "<!DOCTYPE html><html><body><p>hello</p></body></html>"
        let draft = MailDraft(
            to: "a@b.c", cc: nil, subject: "hi", body: "hello", bodyHTML: html
        )
        let id = try await outbox.enqueue(draft, account: account)

        let stored = try #require(try store.outboxItem(account: account, id: id))
        #expect(stored.bodyHTML == html)
        #expect(stored.body == "hello")

        let outcome = await outbox.flushOnce(account: account)
        #expect(outcome == .sent(id))
        let mime = String(decoding: await gateway.sentMIME[0], as: UTF8.self)
        #expect(mime.contains("multipart/alternative"))
        #expect(mime.contains("Content-Type: text/html; charset=utf-8"))
        #expect(mime.contains(Data(html.utf8).base64EncodedString(options: [.lineLength76Characters])))
    }

    @Test("flushOnce returns nil when nothing is deliverable")
    func nothingToDo() async throws {
        let (_, account, gateway, _, outbox) = try fixture()

        let outcome = await outbox.flushOnce(account: account)

        #expect(outcome == nil)
        #expect(await gateway.attempts == 0)
    }

    @Test("an offline failure keeps the row and schedules the first retry 30s out")
    func offlineBackoff() async throws {
        let (_, account, gateway, clock, outbox) = try fixture(gateway: FakeGateway(outcomes: [.offline]))
        let id = try await outbox.enqueue(makeDraft(), account: account)

        let outcome = await outbox.flushOnce(account: account)

        #expect(outcome == .retryScheduled(id, error: .offline, nextAttempt: clock.now.addingTimeInterval(30)))
        let pending = try await outbox.pending(account: account)
        #expect(pending.count == 1)
        #expect(pending.first?.state == "failed_retryable")
        #expect(pending.first?.attempts == 1)
        #expect(pending.first?.lastError == "offline")
        #expect(pending.first?.body == "text")
        #expect(pending.first?.nextAttemptAt == clock.now.addingTimeInterval(30))
        #expect(await gateway.attempts == 1)
    }

    @Test("a retryable row is not claimed again before its next attempt")
    func retryWaitsForBackoff() async throws {
        let (_, account, gateway, clock, outbox) = try fixture(gateway: FakeGateway(outcomes: [.offline]))
        let id = try await outbox.enqueue(makeDraft(), account: account)
        _ = await outbox.flushOnce(account: account)

        clock.advance(by: 29)
        let early = await outbox.flushOnce(account: account)
        #expect(early == nil)
        #expect(await gateway.attempts == 1)

        clock.advance(by: 1)
        let outcome = await outbox.flushOnce(account: account)
        #expect(outcome == .sent(id))
        #expect(await gateway.attempts == 2)
    }

    @Test("offline enqueue recovers later and delivers exactly once")
    func offlineThenRecovers() async throws {
        let (_, account, gateway, clock, outbox) = try fixture(gateway: FakeGateway(outcomes: [.offline]))
        let id = try await outbox.enqueue(makeDraft(), account: account)

        let first = await outbox.flushOnce(account: account)
        #expect(first?.error == .offline)

        clock.advance(by: 30)
        let second = await outbox.flushOnce(account: account)
        #expect(second == .sent(id))
        let third = await outbox.flushOnce(account: account)
        #expect(third == nil)
        #expect(await gateway.attempts == 2)
        #expect(await gateway.clientIDs == [id.raw], "exactly one successful delivery")
    }

    @Test(
        "permanent failures keep the row and are never auto-retried",
        arguments: [MailError.authFailed, .deviceNotRegistered, .policyBlocked, .unsupported]
    )
    func permanentFailure(error: MailError) async throws {
        let (_, account, gateway, clock, outbox) = try fixture(gateway: FakeGateway(outcomes: [error]))
        let id = try await outbox.enqueue(makeDraft(), account: account)

        let outcome = await outbox.flushOnce(account: account)

        #expect(outcome == .failedPermanent(id, error: error))
        let state = try await outbox.state(of: id, account: account)
        #expect(state == .failedPermanent)
        let pending = try await outbox.pending(account: account)
        #expect(pending.first?.attempts == 1)
        #expect(pending.first?.nextAttemptAt == nil)
        #expect(pending.first?.lastError == String(describing: error))

        clock.advance(by: 86_400)
        let later = await outbox.flushOnce(account: account)
        #expect(later == nil)
        #expect(await gateway.attempts == 1, "permanent failures wait for a manual retry")
    }

    @Test("manual retry puts a permanent failure back in the queue and delivers it")
    func manualRetry() async throws {
        let (_, account, gateway, _, outbox) = try fixture(gateway: FakeGateway(outcomes: [.authFailed]))
        let id = try await outbox.enqueue(makeDraft(), account: account)
        _ = await outbox.flushOnce(account: account)

        try await outbox.retry(id, account: account)
        let queued = try await outbox.state(of: id, account: account)
        #expect(queued == .queued)

        let outcome = await outbox.flushOnce(account: account)
        #expect(outcome == .sent(id))
    }

    @Test("an expired sending lease can be reclaimed; a live lease cannot")
    func leaseExpiry() async throws {
        let (store, account, gateway, clock, outbox) = try fixture()
        let id = try await outbox.enqueue(makeDraft(), account: account)

        let claimed = try #require(try store.claimOutbox(account: account, now: clock.now, lease: .seconds(120)))
        #expect(claimed.id == id.raw)
        #expect(claimed.state == "sending")

        clock.advance(by: 60)
        let live = await outbox.flushOnce(account: account)
        #expect(live == nil, "a live lease protects the in-flight delivery")

        clock.advance(by: 61)
        let reclaimed = await outbox.flushOnce(account: account)
        #expect(reclaimed == .sent(id))
        #expect(await gateway.attempts == 1)
    }

    @Test("cancel moves a queued row to canceled and it is never delivered")
    func cancelQueued() async throws {
        let (_, account, gateway, _, outbox) = try fixture()
        let id = try await outbox.enqueue(makeDraft(), account: account)

        try await outbox.cancel(id, account: account)

        let state = try await outbox.state(of: id, account: account)
        #expect(state == .canceled)
        let pending = try await outbox.pending(account: account)
        #expect(pending.isEmpty)
        let outcome = await outbox.flushOnce(account: account)
        #expect(outcome == nil)
        #expect(await gateway.attempts == 0)
    }

    @Test("cancel also works on a failed retryable row")
    func cancelFailedRetryable() async throws {
        let (_, account, _, clock, outbox) = try fixture(gateway: FakeGateway(outcomes: [.offline]))
        let id = try await outbox.enqueue(makeDraft(), account: account)
        _ = await outbox.flushOnce(account: account)

        try await outbox.cancel(id, account: account)
        let state = try await outbox.state(of: id, account: account)
        #expect(state == .canceled)

        clock.advance(by: 3_600)
        let outcome = await outbox.flushOnce(account: account)
        #expect(outcome == nil)
    }

    @Test("a cancel request during sending settles to canceled when delivery fails")
    func cancelDuringSending() async throws {
        let (store, account, _, clock, outbox) = try fixture(gateway: FakeGateway(outcomes: [.offline]))
        let id = try await outbox.enqueue(makeDraft(), account: account)
        // Simulate an in-flight claim from this or another process.
        _ = try store.claimOutbox(account: account, now: clock.now, lease: .seconds(120))

        try await outbox.cancel(id, account: account)
        let whileSending = try await outbox.state(of: id, account: account)
        #expect(whileSending == .sending, "cancel while sending only records the intent")

        clock.advance(by: 121)
        let outcome = await outbox.flushOnce(account: account)
        #expect(outcome == .canceled(id))
        let settled = try await outbox.state(of: id, account: account)
        #expect(settled == .canceled)
    }

    @Test("flushAll drains every deliverable row")
    func flushAllDrains() async throws {
        let (_, account, gateway, _, outbox) = try fixture()
        let first = try await outbox.enqueue(makeDraft(), account: account)
        let second = try await outbox.enqueue(makeDraft(), account: account)

        let outcomes = await outbox.flushAll(account: account)

        #expect(outcomes == [.sent(first), .sent(second)])
        let pending = try await outbox.pending(account: account)
        #expect(pending.isEmpty)
        #expect(await gateway.attempts == 2)
    }

    @Test("a send that outlives the timeout is a retryable offline failure")
    func timeoutIsRetryable() async throws {
        let (_, account, gateway, _, outbox) = try fixture(
            gateway: FakeGateway(delay: .seconds(5)),
            sendTimeout: .milliseconds(50)
        )
        let id = try await outbox.enqueue(makeDraft(), account: account)

        let outcome = await outbox.flushOnce(account: account)

        #expect(outcome?.outboxID == id)
        #expect(outcome?.error == .offline)
        let state = try await outbox.state(of: id, account: account)
        #expect(state == .failedRetryable)
        #expect(await gateway.attempts == 1)
    }

    @Test("a row whose account vanished fails permanently instead of sending")
    func missingAccount() async throws {
        let (store, account) = try seededStore()
        let gateway = FakeGateway()
        let outbox = Outbox(store: store, gateway: gateway, clock: TestClock())
        let orphan = AccountID("missing")
        let id = try await outbox.enqueue(makeDraft(), account: orphan)

        let outcome = await outbox.flushOnce(account: orphan)

        guard case .failedPermanent(let outcomeID, let error)? = outcome, case .invalidInput = error else {
            Issue.record("expected a permanent invalidInput failure, got \(String(describing: outcome))")
            return
        }
        #expect(outcomeID == id)
        let state = try await outbox.state(of: id, account: orphan)
        #expect(state == .failedPermanent)
        #expect(await gateway.attempts == 0)
        // The real account is untouched.
        #expect(try store.pendingOutbox(account: account).isEmpty)
    }
}

@Suite("Outbox backoff")
struct OutboxBackoffTests {
    @Test(
        "retry delays follow 30s, 2m, 10m, 30m then double up to the 24h cap",
        arguments: [
            (1, 30.0), (2, 120.0), (3, 600.0), (4, 1_800.0),
            (5, 3_600.0), (6, 7_200.0), (8, 28_800.0), (20, 86_400.0),
        ]
    )
    func schedule(failedAttempts: Int, expected: TimeInterval) {
        #expect(OutboxBackoff.delay(failedAttempts: failedAttempts) == expected)
    }

    @Test(
        "the permanent/retryable split matches the contract table",
        arguments: [
            (MailError.authFailed, true),
            (.deviceNotRegistered, true),
            (.policyBlocked, true),
            (.unsupported, true),
            (.offline, false),
            (.throttled(seconds: 5), false),
            (.syncKeyInvalid, false),
            (.storage(reason: "disk"), false),
            (.invalidInput(reason: "bad"), false),
        ]
    )
    func classification(error: MailError, permanent: Bool) {
        #expect(OutboxBackoff.isPermanent(error) == permanent)
    }

    @Test("throttled uses the server Retry-After value")
    func throttledHonoursRetryAfter() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let next = OutboxBackoff.nextAttempt(after: .throttled(seconds: 90), failedAttempts: 1, now: now)
        #expect(next == now.addingTimeInterval(90))
    }

    @Test("throttled without Retry-After falls back to the schedule")
    func throttledWithoutRetryAfter() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let next = OutboxBackoff.nextAttempt(after: .throttled(seconds: nil), failedAttempts: 1, now: now)
        #expect(next == now.addingTimeInterval(30))
    }
}

@Suite("Outbox MIME")
struct OutboxMimeTests {
    @Test("MIME has the headers the gateway needs and a base64 body")
    func mimeShape() {
        let draft = Draft(
            to: "a@b.c", cc: "c@d.e", subject: "周报",
            body: "line1\nline2", inReplyTo: "<id@x>", references: "<id@x>"
        )
        let data = MimeBuilder.build(from: "me@corp.test", draft: draft, messageID: "new@corp.test")
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("From: me@corp.test"))
        #expect(text.contains("To: a@b.c"))
        #expect(text.contains("Cc: c@d.e"))
        #expect(text.contains("Subject: =?UTF-8?B?"), "non-ASCII subject must be RFC 2047 encoded")
        #expect(text.contains("In-Reply-To: <id@x>"))
        #expect(text.contains("References: <id@x>"))
        #expect(text.contains("Content-Transfer-Encoding: base64"))
        #expect(text.contains(Data("line1\nline2".utf8).base64EncodedString(options: [.lineLength76Characters])))
    }

    @Test("an autocomplete-inserted address keeps the To/Cc headers ASCII")
    func autocompleteAddressHeaderIsAscii() {
        let draft = Draft(
            to: "li.si@corp.test; zhang.san@corp.test;",
            cc: "alice@corp.test;",
            subject: "hi",
            body: "text"
        )
        let data = MimeBuilder.build(from: "me@corp.test", draft: draft, messageID: "new@corp.test")
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("To: li.si@corp.test; zhang.san@corp.test;"))
        #expect(text.contains("Cc: alice@corp.test;"))
        #expect(!text.contains("张三"))
        // Only the (ASCII) subject/header lines matter here; the body is base64.
        let headers = text.components(separatedBy: "\r\n\r\n").first ?? ""
        #expect(headers.unicodeScalars.allSatisfy { $0.value < 128 })
    }

    @Test("an HTML body becomes multipart/alternative with both base64 payloads")
    func mimeMultipart() {
        let html = "<!DOCTYPE html><html><body><p>hello</p></body></html>"
        let draft = Draft(
            to: "a@b.c", cc: nil, subject: "hi", body: "hello\n", bodyHTML: html
        )
        let text = String(
            decoding: MimeBuilder.build(from: "me@corp.test", draft: draft, messageID: "new@corp.test"),
            as: UTF8.self
        )

        #expect(text.contains("Content-Type: multipart/alternative; boundary=\"uumail-"))
        #expect(text.contains("Content-Type: text/plain; charset=utf-8"))
        #expect(text.contains("Content-Type: text/html; charset=utf-8"))
        #expect(text.contains(Data("hello\n".utf8).base64EncodedString(options: [.lineLength76Characters])))
        #expect(text.contains(Data(html.utf8).base64EncodedString(options: [.lineLength76Characters])))
        let marker = "boundary=\""
        let start = text.range(of: marker)?.upperBound
        let end = start.flatMap { text[$0...].firstIndex(of: "\"") }
        let boundary = start.flatMap { start in end.map { String(text[start..<$0]) } }
        #expect(boundary != nil)
        if let boundary {
            #expect(text.contains("--\(boundary)--"), "the multipart boundary is closed")
        }
    }

    @Test("blank HTML keeps the plain-text-only MIME shape")
    func blankHTMLFallsBack() {
        let draft = Draft(
            to: "a@b.c", cc: nil, subject: "hi", body: "text", bodyHTML: "   "
        )
        let text = String(
            decoding: MimeBuilder.build(from: "me@corp.test", draft: draft, messageID: "new@corp.test"),
            as: UTF8.self
        )

        #expect(text.contains("Content-Type: text/plain; charset=utf-8"))
        #expect(!text.contains("multipart/alternative"))
    }
}
