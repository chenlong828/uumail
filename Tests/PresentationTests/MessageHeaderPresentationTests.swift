import Foundation
import MailDomain
import Testing

@testable import Presentation

@Suite("MessageHeaderPresentation")
struct MessageHeaderPresentationTests {
    @Test("a complete envelope maps the subject and four rows in fixed order")
    func completeEnvelope() {
        let raw = "2026-11-16T09:30:00Z"
        let header = MessageHeaderPresentation(message: Message(
            serverID: "S-1",
            subject: "季度评审",
            sender: "\"赵六\" <zhao@example.com>",
            recipients: "\"李四\" <li@example.com>",
            receivedRaw: raw,
            cc: "\"王五\" <wang@example.com>"
        ))

        #expect(header.subject == "季度评审")
        #expect(header.rows.map(\.label) == ["发件人", "收件人", "抄送", "时间"])
        #expect(header.rows.map(\.value) == [
            "\"赵六\" <zhao@example.com>",
            "\"李四\" <li@example.com>",
            "\"王五\" <wang@example.com>",
            DisplayFormat.messageDate(raw),
        ])
        #expect(header.rows.map(\.lineLimit) == [1, 2, 2, 1])
        #expect(Set(header.rows.map(\.id)).count == header.rows.count, "row identities must stay unique")
    }

    @Test("a sparse envelope drops empty rows and uses the subject/date fallbacks")
    func sparseEnvelope() {
        let raw = "not-a-date"
        let header = MessageHeaderPresentation(message: Message(
            serverID: "S-2",
            subject: nil,
            sender: "li@example.com",
            recipients: "zhang@example.com",
            receivedRaw: raw,
            cc: "   "
        ))

        #expect(header.subject == "(无主题)")
        #expect(header.rows.map(\.label) == ["发件人", "收件人", "时间"])
        #expect(header.rows.first { $0.label == "时间" }?.value == String(raw.prefix(16)))
        #expect(!header.rows.contains { $0.label == "抄送" })
        #expect(!header.rows.contains { $0.value.isEmpty })
    }

    @Test("nil or blank fields produce no rows and no empty labels")
    func blankFields() {
        let header = MessageHeaderPresentation(message: Message(
            serverID: "S-3",
            subject: "  ",
            sender: "  ",
            recipients: "\n",
            receivedRaw: "   ",
            cc: nil
        ))

        #expect(header.subject == "(无主题)")
        #expect(header.rows.isEmpty)
    }

    @Test("envelope values are trimmed but keep the display name and address")
    func trimsEnvelopeValues() {
        let header = MessageHeaderPresentation(message: Message(
            serverID: "S-4",
            subject: "  主题  ",
            sender: "  \"赵六\" <zhao@example.com>  ",
            recipients: "\n li@example.com \n"
        ))

        #expect(header.subject == "主题")
        #expect(header.rows.first { $0.label == "发件人" }?.value == "\"赵六\" <zhao@example.com>")
        #expect(header.rows.first { $0.label == "收件人" }?.value == "li@example.com")
    }

    @Test("a nil received date produces no time row")
    func nilDateDropsTimeRow() {
        let header = MessageHeaderPresentation(message: Message(
            serverID: "S-5",
            subject: "无时间",
            sender: "a@example.com",
            receivedRaw: nil
        ))

        #expect(header.rows.map(\.label) == ["发件人"])
    }

    @Test("equal messages derive equal headers")
    func equalityFollowsMessage() {
        let message = Message(
            serverID: "S-6",
            subject: "主题",
            sender: "a@example.com",
            recipients: "b@example.com",
            receivedRaw: "2026-11-16T09:30:00Z"
        )
        let other = Message(
            serverID: "S-6",
            subject: "另一个主题",
            sender: "a@example.com",
            recipients: "b@example.com",
            receivedRaw: "2026-11-16T09:30:00Z"
        )

        #expect(MessageHeaderPresentation(message: message) == MessageHeaderPresentation(message: message))
        #expect(MessageHeaderPresentation(message: message) != MessageHeaderPresentation(message: other))
    }
}
