import Foundation
import MailDomain
import Scenes

/// Body loading lives in its own file so the mailbox state machine stays under the
/// component line budget. Same component; no new public API.
extension MailboxViewModel {

    /// Opens the selected message: cached body immediately, otherwise a preview while
    /// the scene fetches. A second call for the same message joins the in-flight open.
    public func openSelected() async {
        guard let ref = selectedRef else {
            clearBody()
            return
        }
        if openedBody == ref, case .loaded = body { return }
        if let inFlight = bodyTask, openingRef == ref {
            await inFlight.value
            return
        }

        bodyTask?.cancel()
        bodyTask = nil
        openingRef = ref
        openedBody = nil
        body = .none
        bodyNotice = nil
        attachments = (try? read.attachments(for: ref)) ?? []

        let cached: String?
        do {
            cached = try read.bodyIfCached(ref)
        } catch {
            cached = nil
        }
        if let cached, !cached.isEmpty {
            body = .loaded(html: cached, truncated: false)
            openedBody = ref
            openingRef = nil
            return
        }

        if let preview = Self.previewHTML(for: selectedMessage?.bodyPreview) {
            body = .loaded(html: preview, truncated: false)
            bodyNotice = .fetchingFullBody
        } else {
            body = .loading
        }

        let stream = read.open(ref)
        let task = Task { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { break }
                self.apply(event, for: ref)
            }
        }
        bodyTask = task
        await task.value
        if openingRef == ref {
            openingRef = nil
            bodyTask = nil
        }
    }

    func startBodyLoad() {
        Task { await self.openSelected() }
    }

    func apply(_ event: BodyEvent, for ref: MessageRef) {
        guard selectedRef == ref else { return }
        switch event {
        case .cached(let html):
            body = .loaded(html: html, truncated: false)
            bodyNotice = nil
            openedBody = ref
        case .loaded(let fetched):
            body = .loaded(html: fetched.text, truncated: fetched.isTruncated)
            bodyNotice = nil
            openedBody = ref
        case .failed(let error):
            let text = ErrorText.text(for: error)
            if case .loaded(let html, let truncated) = body, bodyNotice != nil {
                // Keep the preview readable; the no-preview case falls back to retry.
                body = .loaded(html: html, truncated: truncated)
                bodyNotice = .previewFallback(text: text)
            } else {
                body = .failed(text: text)
                bodyNotice = nil
            }
        }
    }

    func clearBody() {
        bodyTask?.cancel()
        bodyTask = nil
        openingRef = nil
        openedBody = nil
        body = .none
        bodyNotice = nil
        attachments = []
    }

    static func previewHTML(for preview: String?) -> String? {
        guard let preview else { return nil }
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return HTMLText.fromPlainText(trimmed)
    }
}
