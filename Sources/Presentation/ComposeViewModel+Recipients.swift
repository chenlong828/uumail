import Foundation
import MailDomain

/// Recipient autocomplete state machine. The stored state lives on `ComposeViewModel`
/// so Observation tracks it; the methods are split out to keep the main file within its
/// 400-line budget.
extension ComposeViewModel {
    // MARK: - Recipient suggestions

    /// Focus entered a field: remember it and load the local directory at most once.
    public func recipientFocusChanged(in field: RecipientField) {
        activeRecipientField = field
        ensureRecipientDirectoryLoaded()
        if !RecipientText.tailFragment(in: text(for: field)).isEmpty {
            refreshRecipientSuggestions(in: field)
        } else {
            clearRecipientSuggestions()
        }
    }

    /// Focus left the address fields: close the panel and forget the owner.
    public func recipientFocusLost() {
        activeRecipientField = nil
        clearRecipientSuggestions()
    }

    /// The field text changed. A caret in the middle disables completion so a selection
    /// can never rewrite text on both sides of the insertion point.
    public func recipientTextChanged(in field: RecipientField, caretAtEnd: Bool) {
        activeRecipientField = field
        guard caretAtEnd else {
            clearRecipientSuggestions()
            return
        }
        refreshRecipientSuggestions(in: field)
    }

    /// The caret moved without a text change.
    public func recipientCaretChanged(atEnd: Bool) {
        guard let field = activeRecipientField else {
            clearRecipientSuggestions()
            return
        }
        guard atEnd else {
            clearRecipientSuggestions()
            return
        }
        refreshRecipientSuggestions(in: field)
    }

    /// Moves the highlight within the list. First Down highlights the first row, first
    /// Up the last; both stop at the ends instead of wrapping.
    public func moveRecipientHighlight(by delta: Int) {
        guard !recipientSuggestions.isEmpty else {
            highlightedSuggestion = nil
            return
        }
        let count = recipientSuggestions.count
        let current: Int
        if let highlightedSuggestion {
            current = highlightedSuggestion
        } else {
            current = delta > 0 ? -1 : count
        }
        highlightedSuggestion = min(max(current + delta, 0), count - 1)
    }

    /// Commits one row into the active field's trailing fragment. Only the tail changes;
    /// the other field, subject and editor stay untouched.
    @discardableResult
    public func selectRecipientSuggestion(at index: Int) -> Bool {
        guard let field = activeRecipientField,
              recipientSuggestions.indices.contains(index)
        else { return false }
        let current = text(for: field)
        let updated = RecipientText.replacingTail(
            in: current,
            with: recipientSuggestions[index].address
        )
        guard updated != current else { return false }
        switch field {
        case .to: to = updated
        case .cc: cc = updated
        }
        clearRecipientSuggestions()
        return true
    }

    /// Return/Tab path. Without a user-moved highlight it does nothing.
    @discardableResult
    public func selectHighlightedRecipientSuggestion() -> Bool {
        guard let highlightedSuggestion,
              recipientSuggestions.indices.contains(highlightedSuggestion)
        else { return false }
        return selectRecipientSuggestion(at: highlightedSuggestion)
    }

    /// Esc/outside-click path: close the panel but keep the field active.
    public func dismissRecipientSuggestions() {
        clearRecipientSuggestions()
    }

    private func ensureRecipientDirectoryLoaded() {
        guard recipientDirectory == nil else { return }
        directoryLoadCount += 1
        recipientDirectory = scene.recipientDirectory(account: account)
    }

    private func refreshRecipientSuggestions(in field: RecipientField) {
        ensureRecipientDirectoryLoaded()
        let current = text(for: field)
        let fragment = RecipientText.tailFragment(in: current)
        guard !fragment.isEmpty else {
            clearRecipientSuggestions()
            return
        }

        var excluding = AddressList(RecipientText.prefixBeforeTail(in: current)).addresses
        let other = field == .to ? cc : to
        excluding.append(contentsOf: AddressList(other).addresses)
        recipientSuggestions = recipientDirectory?.suggestions(
            for: fragment,
            excluding: excluding,
            limit: 8
        ) ?? []
        highlightedSuggestion = nil
    }

    private func clearRecipientSuggestions() {
        recipientSuggestions = []
        highlightedSuggestion = nil
    }

    private func text(for field: RecipientField) -> String {
        switch field {
        case .to: to
        case .cc: cc
        }
    }

}
