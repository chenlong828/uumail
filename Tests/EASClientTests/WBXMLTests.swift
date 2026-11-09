import Foundation
import Testing

@testable import EASClient

extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}

@Suite("WBXML codec")
struct WBXMLTests {
    let codec = try! WBXMLCodec.standard()

    @Test("FolderSync request matches the probe's bytes")
    func folderSyncGolden() throws {
        let element = WBXMLElement.children("FolderSync", [.text("SyncKey", "0")])
        let data = try codec.encode(element)
        #expect(data == Data(hex: "03016a00000756520330000101"))
    }

    @Test("Provision step 1 matches the probe's bytes")
    func provisionGolden() throws {
        let element = WBXMLElement.children("Provision", [
            .children("DeviceInformation", [
                .children("Set", [
                    .text("Model", "MacBookPro"),
                    .text("FriendlyName", "macOS EAS"),
                    .text("OS", "macOS"),
                    .text("UserAgent", "Apple-iPhone18C4/2307.90"),
                ]),
            ]),
            .children("Policies", [
                .children("Policy", [.text("PolicyType", "MS-EAS-Provisioning-WBXML")]),
            ]),
        ])
        let data = try codec.encode(element)
        let expected = """
        03016a00000e450012564857034d6163426f6f6b50726f000159036d61634f532045415300015a036d61634f53000160034170706c652d6950686f6e65313843342f323330372e393000010101000e464748034d532d4541532d50726f766973696f6e696e672d5742584d4c0001010101
        """
        #expect(data == Data(hex: expected.replacingOccurrences(of: "\n", with: "")))
    }

    @Test("Minimal Sync body matches the probe's bytes")
    func syncGolden() throws {
        let element = WBXMLElement.children("Sync", [
            .children("Collections", [
                .children("Collection", [
                    .text("SyncKey", "0"),
                    .text("CollectionId", "13"),
                    .text("WindowSize", "25"),
                ]),
            ]),
        ])
        #expect(try codec.encode(element) == Data(hex: "03016a00455c4f4b03300001520331330001550332350001010101"))
    }

    @Test("Decodes a FolderSync response into a tree")
    func decodesFolderSyncResponse() throws {
        let bytes = Data(hex: "03016a0000075652033100014e4f4803380001490330000147035465737400014a0331000101014c0331000101")
        let root = try codec.decode(bytes)
        let folderSync = try #require(root.child("FolderSync"))
        #expect(folderSync.child("SyncKey")?.stringValue() == "1")
        #expect(folderSync.path("Changes", "Add", "ServerId")?.stringValue() == "8")
        #expect(folderSync.path("Changes", "Add", "DisplayName")?.stringValue() == "Test")
    }

    @Test("Opaque payloads round-trip")
    func opaqueRoundTrip() throws {
        let payload = Data([0x00, 0xFF, 0x10, 0x20])
        let element = WBXMLElement.opaque("Mime", payload)
        let root = try codec.decode(codec.encode(element))
        #expect(root.child("Mime")?.opaque == payload)
    }

    @Test("Unknown tags fail encoding instead of emitting garbage")
    func unknownTagFails() {
        let element = WBXMLElement.text("DefinitelyNotATag", "x")
        #expect(throws: WBXMLError.self) {
            _ = try codec.encode(element)
        }
    }
}
