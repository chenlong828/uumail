import Foundation
import Testing

@testable import MailDomain

@Suite("MailDomain values")
struct MailDomainValueTests {
    @Test("only type 2 is the inbox")
    func inboxType() {
        #expect(Folder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2).isInbox)
        #expect(!Folder(serverID: "4", parentID: "0", displayName: "草稿", type: 3).isInbox)
    }

    @Test("a message defaults to an unread envelope without attachments")
    func messageDefaults() {
        let message = Message(serverID: "101")
        #expect(message.isRead == false)
        #expect(message.folderID == nil)
        #expect(message.attachments.isEmpty)
        #expect(message.subject == nil)
    }

    @Test("an old keychain payload decodes with protocol defaults")
    func legacyConfigurationDecoding() throws {
        let legacy = """
        {"host":"mail.example.com","account":"u","password":"p","domain":"D","deviceID":"dev-1","displayName":"u"}
        """
        let configuration = try JSONDecoder().decode(ServerConfiguration.self, from: Data(legacy.utf8))
        #expect(configuration.host == "mail.example.com")
        #expect(configuration.deviceType == "iPhone")
        #expect(configuration.protocolVersion == "16.1")
        #expect(configuration.allowInsecureTLS == false)

        let encoded = try JSONEncoder().encode(configuration)
        let roundTrip = try JSONDecoder().decode(ServerConfiguration.self, from: encoded)
        #expect(roundTrip == configuration)
    }
}
