import Foundation
import MailDomain
import MailStore
import Testing

@testable import Presentation

/// Verification-node additions for SCN-0017 assertions that the implementation tests did
/// not pin: the loaded directory is a frozen snapshot, selection does not reload it or
/// duplicate an address, switching fields closes the previous panel, and an empty
/// directory leaves manual addressing and sending untouched.
@Suite("Recipient autocomplete edges")
@MainActor
struct RecipientAutocompleteTests {
    private func makeCompose() throws -> (MailboxFixture, ComposeViewModel) {
        let fixture = try makeMailboxFixture(messages: ["13": [
            presentationMessage(
                "1",
                sender: "\"张三\" <zhang.san@corp.test>",
                recipients: "li.si@corp.test",
                receivedRaw: "2026-11-18T09:00:00Z"
            ),
            presentationMessage(
                "2",
                sender: "\"李四\" <li.si@corp.test>",
                receivedRaw: "2026-11-17T09:00:00Z"
            ),
            presentationMessage(
                "3",
                sender: "\"Alice\" <alice@corp.test>",
                receivedRaw: "2026-11-16T09:00:00Z"
            ),
        ]])
        return (fixture, fixture.viewModel.composeNew())
    }

    @Test("the directory snapshot does not change after it is loaded")
    func directorySnapshotStaysFrozenAfterLoad() throws {
        let (fixture, compose) = try makeCompose()
        compose.recipientFocusChanged(in: .to)
        compose.to = "zha"
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(compose.recipientSuggestions.map(\.address) == ["zhang.san@corp.test"])

        // A message that arrives after the snapshot must not enter this compose session.
        try fixture.store.applySyncBatch(
            account: fixture.account,
            folder: "13",
            added: [presentationMessage("new", sender: "zoe@corp.test")],
            changed: [],
            removedServerIDs: [],
            syncKey: "3"
        )

        compose.to = "zoe"
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(compose.recipientSuggestions.isEmpty)
        #expect(compose.directoryLoadCount == 1)
    }

    @Test("selecting a row neither reloads the directory nor duplicates an address")
    func selectionDoesNotReloadOrDuplicate() throws {
        let (_, compose) = try makeCompose()
        compose.to = "li.si@corp.test; zha"
        compose.recipientFocusChanged(in: .to)
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(compose.selectRecipientSuggestion(at: 0))
        #expect(compose.to == "li.si@corp.test; zhang.san@corp.test; ")
        #expect(compose.directoryLoadCount == 1)

        // Typing the completed address again must not resurface it from To.
        compose.to = "li.si@corp.test; zhang.san@corp.test; zhang"
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(compose.recipientSuggestions.isEmpty)
        #expect(compose.directoryLoadCount == 1)
    }

    @Test("switching fields closes the previous field's suggestions")
    func switchingFieldsClearsSuggestions() throws {
        let (_, compose) = try makeCompose()
        compose.recipientFocusChanged(in: .to)
        compose.to = "zha"
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(!compose.recipientSuggestions.isEmpty)

        compose.recipientFocusChanged(in: .cc)
        #expect(compose.recipientSuggestions.isEmpty)
        #expect(compose.highlightedSuggestion == nil)
        #expect(compose.activeRecipientField == .cc)
    }

    @Test("an empty directory leaves manual addressing and sending intact")
    func emptyDirectorySendsManualAddress() async throws {
        let fixture = try makeMailboxFixture(messages: [:])
        let compose = fixture.viewModel.composeNew()
        compose.recipientFocusChanged(in: .to)
        compose.to = "manual@corp.test"
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(compose.recipientSuggestions.isEmpty)
        #expect(compose.directoryLoadCount == 1)

        compose.subject = "manual"
        compose.body = "text"
        #expect(await compose.send())
        let pending = try #require(try fixture.store.outbox.pendingOutbox(account: fixture.account).first)
        #expect(pending.to == "manual@corp.test")
    }
}
