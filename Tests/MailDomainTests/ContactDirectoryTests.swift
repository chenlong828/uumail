import Foundation
import Testing

@testable import MailDomain

@Suite("Contact directory")
struct ContactDirectoryTests {
    private func envelope(
        sender: String? = nil,
        recipients: String? = nil,
        cc: String? = nil,
        received: String? = nil
    ) -> ContactEnvelope {
        ContactEnvelope(sender: sender, recipients: recipients, cc: cc, receivedRaw: received)
    }

    @Test("builds named and unnamed candidates from every envelope header")
    func buildsNameAndFallback() {
        let directory = ContactDirectory(
            envelopes: [
                envelope(
                    sender: "\"张三\" <zhang.san@corp.test>",
                    recipients: "\"李四\" <li.si@corp.test>; wang@corp.test",
                    cc: "\"Alice\" <alice@corp.test>",
                    received: "2026-11-18T02:00:00Z"
                ),
                envelope(sender: "noname@corp.test", received: "2026-11-18T01:00:00Z"),
            ]
        )

        #expect(!directory.isEmpty)
        #expect(
            directory.suggestions(for: "zhang")
                == [ContactAddress(name: "张三", address: "zhang.san@corp.test")]
        )
        #expect(
            directory.suggestions(for: "wang")
                == [ContactAddress(name: nil, address: "wang@corp.test")]
        )
        #expect(
            directory.suggestions(for: "noname")
                == [ContactAddress(name: nil, address: "noname@corp.test")]
        )
        #expect(ContactAddress(name: nil, address: "Z@Corp.Test").id == "z@corp.test")

        let empty = ContactDirectory(envelopes: [])
        #expect(empty.isEmpty)
        #expect(empty.suggestions(for: "z").isEmpty)
    }

    @Test("the most recent non-empty name wins regardless of aggregate order")
    func mostRecentNonEmptyNameWins() {
        let newer = envelope(
            sender: "\"New Name\" <same@corp.test>",
            received: "2026-11-18T09:00:00Z"
        )
        let older = envelope(
            sender: "\"Old Name\" <same@corp.test>",
            received: "2026-11-17T09:00:00Z"
        )
        let unnamed = envelope(sender: "same@corp.test", received: "2026-11-19T09:00:00Z")

        for envelopes in [[newer, older], [older, newer], [older, newer, unnamed]] {
            let directory = ContactDirectory(envelopes: envelopes)
            #expect(
                directory.suggestions(for: "same")
                    == [ContactAddress(name: "New Name", address: "same@corp.test")]
            )
        }

        let sameTimestamp = ContactDirectory(
            envelopes: [
                envelope(sender: "\"First\" <tie@corp.test>", received: "2026-11-18T09:00:00Z"),
                envelope(sender: "\"Second\" <tie@corp.test>", received: "2026-11-18T09:00:00Z"),
            ]
        )
        #expect(sameTimestamp.suggestions(for: "tie").first?.name == "First")
    }

    @Test("addresses deduplicate case-insensitively and keep the first spelling")
    func dedupesCaseInsensitively() {
        let directory = ContactDirectory(
            envelopes: [
                envelope(sender: "\"One\" <Z@Corp.Test>", received: "2026-11-18T01:00:00Z"),
                envelope(sender: "\"Two\" <z@corp.test>", received: "2026-11-18T02:00:00Z"),
            ]
        )

        let matches = directory.suggestions(for: "z@corp")
        #expect(matches.count == 1)
        #expect(matches.first == ContactAddress(name: "Two", address: "Z@Corp.Test"))
    }

    @Test("query ordering is address prefix, name prefix, address substring, name substring")
    func matchesAddressAndNameStably() {
        let directory = ContactDirectory(
            envelopes: [
                envelope(sender: "\"Beta\" <alpha@corp.test>", received: "2026-11-18T01:00:00Z"),
                envelope(sender: "\"Alpha\" <beta@corp.test>", received: "2026-11-18T02:00:00Z"),
                envelope(sender: "\"Alphabet\" <gamma@corp.test>", received: "2026-11-18T03:00:00Z"),
            ]
        )

        #expect(
            directory.suggestions(for: "al").map(\.address)
                == ["alpha@corp.test", "gamma@corp.test", "beta@corp.test"]
        )
        #expect(
            directory.suggestions(for: "bet").map(\.address)
                == ["beta@corp.test", "alpha@corp.test", "gamma@corp.test"]
        )
        #expect(
            directory.suggestions(for: "pha").map(\.address)
                == ["alpha@corp.test", "gamma@corp.test", "beta@corp.test"]
        )

        let first = directory.suggestions(for: "corp").map(\.id)
        let second = directory.suggestions(for: "corp").map(\.id)
        #expect(first == second)
        #expect(first.count == 3)
    }

    @Test("matching is case-insensitive and excludes filled addresses")
    func matchesCaseInsensitivelyAndExcludes() {
        let directory = ContactDirectory(
            envelopes: [
                envelope(sender: "\"Zhang San\" <Zhang.San@Corp.Test>", received: "2026-11-18T01:00:00Z"),
                envelope(sender: "\"Zhang Wei\" <zhang.wei@corp.test>", received: "2026-11-18T02:00:00Z"),
            ]
        )

        #expect(
            directory.suggestions(for: "ZHANG.SAN").map(\.address)
                == ["Zhang.San@Corp.Test"]
        )
        #expect(
            directory.suggestions(
                for: "zhang",
                excluding: ["zhang.san@corp.test"]
            ).map(\.address) == ["zhang.wei@corp.test"]
        )
        #expect(directory.suggestions(for: "zhang", excluding: ["  "]).count == 2)
    }

    @Test("blank fragments and out-of-range limits return nothing")
    func blankFragmentAndClampedLimit() {
        let directory = ContactDirectory(
            envelopes: (0..<10).map { index in
                envelope(
                    sender: "user\(index)@corp.test",
                    received: "2026-11-\(String(format: "%02d", index + 1))T01:00:00Z"
                )
            }
        )

        #expect(directory.suggestions(for: "").isEmpty)
        #expect(directory.suggestions(for: "   ").isEmpty)
        #expect(directory.suggestions(for: "user", limit: 0).isEmpty)
        #expect(directory.suggestions(for: "user", limit: -3).isEmpty)
        #expect(directory.suggestions(for: "user", limit: 8).count == 8)
        #expect(directory.suggestions(for: "user", limit: 99).count == 8)
    }

    @Test("skips bare groups, DNs, malformed angle bodies and encoded names")
    func skipsBareGroupsDNsAndMalformedSegments() {
        let directory = ContactDirectory(
            envelopes: [
                envelope(
                    sender: "张三; team; /O=Corp/OU=Exchange/CN=Recipients/CN=z; CN=z",
                    recipients: "Name <>; Team <team>; Team <a@x;b@y>; Unclosed <u@corp.test",
                    cc: "=?UTF-8?B?5byg5LiJ?= <encoded@corp.test>; good@corp.test",
                    received: "2026-11-18T01:00:00Z"
                )
            ]
        )

        #expect(directory.suggestions(for: "good").map(\.address) == ["good@corp.test"])
        #expect(directory.suggestions(for: "team").isEmpty)
        #expect(directory.suggestions(for: "cn=").isEmpty)
        #expect(directory.suggestions(for: "张三").isEmpty)
        #expect(directory.suggestions(for: "a@x").isEmpty)
        #expect(directory.suggestions(for: "u@corp").isEmpty)
        #expect(
            directory.suggestions(for: "encoded")
                == [ContactAddress(name: nil, address: "encoded@corp.test")]
        )
    }

    @Test("quoted commas stay in the display name and angle separators stay in one segment")
    func quotedAndAngledSeparators() {
        let directory = ContactDirectory(
            envelopes: [
                envelope(
                    sender: "\"Doe, John\" <jdoe@corp.test>",
                    recipients: "Team <a@x,b@y>; kept@corp.test",
                    received: "2026-11-18T01:00:00Z"
                )
            ]
        )

        #expect(
            directory.suggestions(for: "doe")
                == [ContactAddress(name: "Doe, John", address: "jdoe@corp.test")]
        )
        #expect(directory.suggestions(for: "a@x").isEmpty)
        #expect(directory.suggestions(for: "b@y").isEmpty)
        #expect(directory.suggestions(for: "kept").count == 1)
    }

    @Test("a name equal to the address or an empty name is dropped")
    func nameFallbackEdges() {
        let directory = ContactDirectory(
            envelopes: [
                envelope(sender: "same@corp.test <same@corp.test>", received: "2026-11-18T01:00:00Z"),
                envelope(sender: "<blank@corp.test>", received: "2026-11-18T00:00:00Z"),
            ]
        )

        #expect(directory.suggestions(for: "same").first?.name == nil)
        #expect(directory.suggestions(for: "blank").first?.name == nil)
    }
}

@Suite("Recipient text")
struct RecipientTextTests {
    @Test("tail fragments, prefixes and replacements preserve the preceding text")
    func tailFragmentAndReplacement() {
        let seeded = "li.si@corp.test; zha"
        #expect(RecipientText.tailFragment(in: seeded) == "zha")
        #expect(RecipientText.prefixBeforeTail(in: seeded) == "li.si@corp.test; ")
        #expect(
            RecipientText.replacingTail(in: seeded, with: "zhang.san@corp.test")
                == "li.si@corp.test; zhang.san@corp.test; "
        )
    }

    @Test("a field with no separator is a single trailing fragment")
    func noSeparator() {
        #expect(RecipientText.tailFragment(in: "  zha  ") == "zha")
        #expect(RecipientText.prefixBeforeTail(in: "  zha  ") == "")
        #expect(RecipientText.replacingTail(in: "zha", with: "z@corp.test") == "z@corp.test; ")
    }

    @Test("quotes and angle brackets suspend separators")
    func quotedAndAngledSeparators() {
        let quoted = "\"Doe, John\" <j@corp.test>, zh"
        #expect(RecipientText.tailFragment(in: quoted) == "zh")
        #expect(RecipientText.prefixBeforeTail(in: quoted) == "\"Doe, John\" <j@corp.test>, ")
        #expect(
            RecipientText.replacingTail(in: quoted, with: "z@corp.test")
                == "\"Doe, John\" <j@corp.test>, z@corp.test; "
        )

        let angled = "Team <a@x;b@y>; zh"
        #expect(RecipientText.tailFragment(in: angled) == "zh")
        #expect(RecipientText.prefixBeforeTail(in: angled) == "Team <a@x;b@y>; ")
    }

    @Test("empty text, empty fragments and empty addresses are safe")
    func emptyInputs() {
        #expect(RecipientText.tailFragment(in: "") == "")
        #expect(RecipientText.prefixBeforeTail(in: "") == "")
        #expect(RecipientText.replacingTail(in: "", with: "a@b.c") == "a@b.c; ")
        #expect(RecipientText.replacingTail(in: "zh", with: "   ") == "zh")
        #expect(RecipientText.tailFragment(in: "a@b.c;    ") == "")
    }
}
