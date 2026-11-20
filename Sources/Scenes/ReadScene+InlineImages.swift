import Foundation
import MailDomain

extension ReadScene {
    /// The current body's referenced inline attachments as `data:`-rewritten HTML; `nil`
    /// when nothing usable can be replaced. Cold path: a cache hit never touches the network;
    /// a failed, oversized or cancelled image is skipped without throwing to the UI.
    public func renderInlineImages(for ref: MessageRef, html: String) async -> String? {
        guard let attachments = try? attachments(for: ref), !attachments.isEmpty else { return nil }
        let matches = InlineImageHTML.matches(inHTML: html, attachments: attachments)
        guard !matches.isEmpty else { return nil }

        var payloads: [String: String] = [:]
        var attempted = Set<String>()
        var replacements: [String: String] = [:]
        for match in matches {
            if Task.isCancelled { return nil }
            let fileReference = match.attachment.fileReference
            if attempted.insert(fileReference).inserted {
                if let url = try? await downloadAttachment(match.attachment, in: ref),
                   let data = try? Data(contentsOf: url),
                   data.count <= 20 * 1024 * 1024,
                   let dataURL = InlineImageHTML.dataURL(for: data) {
                    payloads[fileReference] = dataURL
                }
            }
            if let dataURL = payloads[fileReference] { replacements[match.source] = dataURL }
        }
        guard !replacements.isEmpty else { return nil }
        return InlineImageHTML.replacingSources(inHTML: html, with: replacements)
    }
}
