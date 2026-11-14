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
        #expect(message.cc == nil)
    }

    @Test("cc defaults to nil and takes part in message equality")
    func messageCcEquality() {
        let withoutCc = Message(serverID: "101", recipients: "a@corp.test")
        #expect(withoutCc.cc == nil)

        var withCc = withoutCc
        withCc.cc = "c@corp.test"
        #expect(withCc != withoutCc)

        let constructed = Message(serverID: "101", recipients: "a@corp.test", cc: "c@corp.test")
        #expect(withCc == constructed)
    }

    @Test("address lists split display-name envelopes into bare addresses")
    func addressListNormalizesEnvelopes() {
        let list = AddressList(
            "\"张三\" <z@corp.test>; \"Doe, John\" <j@corp.test>, a@corp.test; b@corp.test"
        )
        #expect(list.addresses == ["z@corp.test", "j@corp.test", "a@corp.test", "b@corp.test"])
        #expect(list.text == "z@corp.test; j@corp.test; a@corp.test; b@corp.test")
        #expect(!list.isEmpty)

        #expect(AddressList(nil).addresses.isEmpty)
        #expect(AddressList(" ; , ").text == "")
        #expect(AddressList([nil, "a@corp.test", ""]).addresses == ["a@corp.test"])
    }

    @Test("address lists skip bare display names and keep directory-shaped addresses")
    func addressListKeepsAddressShapes() {
        let list = AddressList(
            "张三; team; /O=Corp/OU=Exchange/CN=Recipients/CN=z; CN=z; \"quoted@corp.test\"; Name <>"
        )
        #expect(list.addresses == ["/O=Corp/OU=Exchange/CN=Recipients/CN=z", "CN=z", "quoted@corp.test"])
        #expect(AddressList("Team <team>").addresses == ["team"])
        #expect(AddressList("Team <a@x;b@y>").addresses == ["a@x;b@y"])
    }

    @Test("address lists deduplicate case-insensitively and keep the first spelling")
    func addressListDeduplicates() {
        let list = AddressList("Z@Corp.Test; a@corp.test; z@corp.test; A@CORP.TEST")
        #expect(list.addresses == ["Z@Corp.Test", "a@corp.test"])
    }

    @Test("address lists merge, remove, and subtract by case-insensitive address")
    func addressListSetOperations() {
        let list = AddressList("b@corp.test; A@corp.test")
        let appended = list.appending(AddressList("a@CORP.test; c@corp.test"))
        #expect(appended.addresses == ["b@corp.test", "A@corp.test", "c@corp.test"])

        #expect(list.removing("a@corp.test").addresses == ["b@corp.test"])
        #expect(list.removing(nil) == list)
        #expect(AddressList("a@x; b@y; c@z").subtracting(AddressList("B@Y; z@z")).addresses == ["a@x", "c@z"])
    }

    @Test("set operations keep group-shaped addresses without re-parsing them")
    func addressListSetOperationsKeepGroupShapedAddresses() {
        let team = AddressList("Team <team>")
        #expect(team.addresses == ["team"])

        let appended = team.appending(AddressList("c@z"))
        #expect(appended.addresses == ["team", "c@z"])

        #expect(team.subtracting(AddressList("c@z")).addresses == ["team"])
        #expect(team.removing("c@z").addresses == ["team"])
    }

    @Test("set operations keep separators inside angle brackets in one address")
    func addressListSetOperationsKeepAngleInternalSeparators() {
        let list = AddressList("Team <a@x;b@y>")
        #expect(list.addresses == ["a@x;b@y"])

        let appended = list.appending(AddressList("c@z"))
        #expect(appended.addresses == ["a@x;b@y", "c@z"])

        #expect(list.subtracting(AddressList("B@Y")).addresses == ["a@x;b@y"])
        #expect(list.removing("c@z").addresses == ["a@x;b@y"])
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

/// Compile-time contract for T-1114-11: the narrow write port has no EAS types and
/// returns a domain `MessageDelta`. This mock lives only in the test target.
private struct RecordingWriteGateway: MailWriteGateway {
    let delta: MessageDelta

    func markRead(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta {
        delta
    }

    func delete(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta {
        delta
    }
}

@Suite("MailWriteGateway contract")
struct MailWriteGatewayTests {
    @Test("the narrow write port returns the server delta unchanged")
    func conformsToWritePort() async throws {
        let delta = MessageDelta(
            added: [Message(serverID: "1")],
            changed: [Message(serverID: "2", isRead: true)],
            removedServerIDs: ["3"],
            syncKey: "9",
            moreAvailable: false
        )
        let gateway = RecordingWriteGateway(delta: delta)

        let read = try await gateway.markRead(collectionID: "13", serverID: "2", syncKey: "8")
        let deleted = try await gateway.delete(collectionID: "13", serverID: "2", syncKey: "8")

        #expect(read == delta)
        #expect(deleted == delta)
    }
}
