import Foundation
import MailDomain
import SyncEngine
import Testing
import SyncContract

@testable import Scenes

@Suite("SyncScene")
struct SyncSceneTests {
    private let clock = FixedClock()

    private func makeScene(
        gateway: FakeGateway,
        store: FakeSyncStore = FakeSyncStore(),
        notifier: FakeNotifier = FakeNotifier(),
        account: AccountID = AccountID("a")
    ) -> SyncScene {
        let engine = SyncEngine(gateway: gateway, store: store, account: account, writeGateway: UnsupportedWriteGateway(), sleeper: { _ in })
        return SyncScene(engine: engine, notifier: notifier, clock: clock)
    }

    @Test("two concurrent refreshes share one SyncEngine run")
    func singleFlight() async throws {
        let gateway = FakeGateway(
            folders: FolderListing(folders: [inboxFolder], syncKey: "7"),
            deltas: makeSyncDeltas(added: 2),
            provisionDelay: .milliseconds(100)
        )
        let scene = makeScene(gateway: gateway)

        async let first = scene.refresh()
        async let second = scene.refresh()
        let (one, two) = await (first, second)

        #expect(one == two, "both callers must receive the same outcome")
        #expect(one.report?.added == 2)
        #expect(one.error == nil)
        #expect(await gateway.provisionCalls == 1, "the second caller joined the in-flight sync")
        #expect(await gateway.folderCalls == 1)
    }

    @Test("new mail asks for permission once and posts the added count")
    func notificationCondition() async throws {
        let gateway = FakeGateway(
            folders: FolderListing(folders: [inboxFolder], syncKey: "7"),
            deltas: makeSyncDeltas(added: 3)
        )
        let notifier = FakeNotifier()
        let scene = makeScene(gateway: gateway, notifier: notifier)

        let outcome = await scene.refresh()

        #expect(outcome.error == nil)
        #expect(outcome.report?.added == 3)
        #expect(outcome.at == clock.now)
        #expect(notifier.authorizationRequests == 1)
        #expect(notifier.posts == [3])
    }

    @Test("a refresh with no new mail posts nothing")
    func noNotificationWithoutNewMail() async throws {
        let gateway = FakeGateway(
            folders: FolderListing(folders: [inboxFolder], syncKey: "7"),
            deltas: makeSyncDeltas(added: 0)
        )
        let notifier = FakeNotifier()
        let scene = makeScene(gateway: gateway, notifier: notifier)

        let outcome = await scene.refresh()

        #expect(outcome.report?.added == 0)
        #expect(notifier.authorizationRequests == 1)
        #expect(notifier.posts.isEmpty)
    }

    @Test("a device rejection does not end the automatic refresh loop")
    func deviceRejectionKeepsTheLoopAlive() async throws {
        // Measured 2026-11-17: a stale SyncKey reaches the app as `200`/zero bytes, i.e. as
        // the same signal as a swallowed request. One occurrence must not kill the loop that
        // is the only thing able to recover; the next tick has to run and clear the text.
        let gateway = FakeGateway(
            folders: FolderListing(folders: [inboxFolder], syncKey: "7"),
            deltas: makeSyncDeltas(added: 1),
            provisionError: .deviceNotRegistered
        )
        let scene = makeScene(gateway: gateway)

        let stream = await scene.startAutoRefresh(every: .milliseconds(1))
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first?.error == .deviceNotRegistered)
        #expect(first?.report == nil)

        await gateway.setProvisionError(nil)
        let second = await iterator.next()
        #expect(second?.report?.added == 1, "the next tick recovers instead of the loop dying")
        await scene.stopAutoRefresh()
    }

    @Test("an auth failure is reported and pauses automatic refresh")
    func authFailurePausesAutoRefresh() async throws {
        let gateway = FakeGateway(
            folders: FolderListing(folders: [inboxFolder], syncKey: "7"),
            deltas: makeSyncDeltas(added: 0),
            provisionError: .authFailed
        )
        let scene = makeScene(gateway: gateway)

        let outcome = await scene.refresh()
        #expect(outcome.report == nil)
        #expect(outcome.error == .authFailed)

        var streamed: [RefreshOutcome] = []
        let stream = await scene.startAutoRefresh(every: .seconds(1))
        for await next in stream {
            streamed.append(next)
        }
        #expect(streamed.isEmpty, "no automatic refresh runs after an auth rejection")

        // A manual refresh still reaches the engine (only the loop is paused).
        let manual = await scene.refresh()
        #expect(manual.error == .authFailed)
        #expect(await gateway.provisionCalls == 2)
    }
}
