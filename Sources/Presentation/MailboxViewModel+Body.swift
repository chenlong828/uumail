import Foundation
import MailDomain
import HTMLSupport
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
        cancelInlineImageRender()
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
            startInlineImageRender(ref, html: cached)
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
            startInlineImageRender(ref, html: html)
        case .loaded(let fetched):
            body = .loaded(html: fetched.text, truncated: fetched.isTruncated)
            bodyNotice = nil
            openedBody = ref
            startInlineImageRender(ref, html: fetched.text)
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
        cancelInlineImageRender()
        openingRef = nil
        openedBody = nil
        body = .none
        bodyNotice = nil
        attachments = []
    }

    /// Starts the cold image render for the body now on screen. The result is applied only
    /// when the selection and the loaded HTML are still the ones this task started from.
    func startInlineImageRender(_ ref: MessageRef, html: String) {
        hideInlineAttachments(inHTML: html)
        inlineImageTask?.cancel()
        inlineImageHTML = nil
        inlineImageTask = Task { [weak self] in
            guard let self else { return }
            let rendered = await self.read.renderInlineImages(for: ref, html: html)
            guard !Task.isCancelled else { return }
            self.applyInlineImageRender(rendered, ref: ref, sourceHTML: html)
        }
    }

    /// The attachment strip lists only files the body does not already render inline.
    /// Inline rendering keeps reading the full attachment list from the scene, so this is a
    /// display projection only; ambiguous or unreferenced sources leave the attachment visible.
    private func hideInlineAttachments(inHTML html: String) {
        let inline = InlineImageReferences.attachmentIDs(inHTML: html, attachments: attachments)
        guard !inline.isEmpty else { return }
        attachments.removeAll { inline.contains($0.fileReference) }
    }

    func cancelInlineImageRender() {
        inlineImageTask?.cancel()
        inlineImageTask = nil
        inlineImageHTML = nil
    }

    private func applyInlineImageRender(_ rendered: String?, ref: MessageRef, sourceHTML: String) {
        guard selectedRef == ref, openedBody == ref,
              case .loaded(let html, _) = body, html == sourceHTML,
              let rendered else { return }
        inlineImageHTML = rendered
    }

    static func previewHTML(for preview: String?) -> String? {
        guard let preview else { return nil }
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return HTMLText.fromPlainText(trimmed)
    }
}
