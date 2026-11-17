import Foundation
import Testing

@testable import Presentation

@Suite("ComposeDocument")
struct ComposeDocumentTests {
    private let email = """
    <!DOCTYPE html><html><head><meta charset="utf-8"><style>p{color:#333}</style></head>
    <body><div>第一行</div></body></html>
    """

    @Test("the editor gets CSP, editor style and contenteditable; capture removes them")
    func roundTrip() {
        let editor = ComposeDocument.editorDocument(emailHTML: email, allowRemoteContent: false)

        #expect(editor.contains("uumail-editor-csp"))
        #expect(editor.contains("Content-Security-Policy"))
        #expect(editor.contains("uumail-editor-style"))
        #expect(editor.contains("contenteditable=\"true\""))
        #expect(editor.contains("spellcheck=\"true\""))

        let captured = ComposeDocument.emailHTML(fromEditorDocument: editor)

        #expect(!captured.contains("uumail-editor-csp"))
        #expect(!captured.contains("uumail-editor-style"))
        #expect(!captured.contains("contenteditable"))
        #expect(!captured.contains("spellcheck"))
        #expect(captured.contains("第一行"))
        #expect(captured.contains("p{color:#333}"), "sender styles survive the round trip")
    }

    @Test("remote images follow the reading-pane permission")
    func remotePermission() {
        let blocked = ComposeDocument.editorDocument(emailHTML: email, allowRemoteContent: false)
        let allowed = ComposeDocument.editorDocument(emailHTML: email, allowRemoteContent: true)

        #expect(blocked.contains("img-src data:;"))
        #expect(!blocked.contains("img-src data: https:"))
        #expect(allowed.contains("img-src data: https: http:;"))
    }

    @Test("an empty draft still yields an editable document")
    func emptyDraft() {
        let editor = ComposeDocument.editorDocument(emailHTML: "", allowRemoteContent: false)

        #expect(editor.contains("contenteditable=\"true\""))
        #expect(editor.contains("uumail-reply-start"))
        #expect(ComposeDocument.emailHTML(fromEditorDocument: editor).contains("uumail-reply-start"))
    }

    @Test("quote headers format the date and keep the sender")
    func quoteHeader() {
        let header = DisplayFormat.quoteHeader(
            sender: "Playasia <newsletter@play-asia.com>",
            receivedRaw: "2026-11-09T12:11:00.000Z"
        )

        #expect(header.contains("2026年11月9日"))
        #expect(header.contains("Playasia <newsletter@play-asia.com>"))
        #expect(header.contains("写道："))
        #expect(DisplayFormat.quoteHeader(sender: nil, receivedRaw: nil) == "原邮件")
    }
}
