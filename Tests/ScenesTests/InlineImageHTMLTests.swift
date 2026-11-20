import Foundation
import MailDomain
import Testing

@testable import Scenes

@Suite("InlineImageHTML")
struct InlineImageHTMLTests {
    private let logo = Attachment(displayName: "logo.png", fileReference: "ref-logo")
    private let photo = Attachment(displayName: "photo.jpg", fileReference: "ref-photo")

    @Test("only cid: values in independent src attributes are collected")
    func sourcesFindCIDSourcesOnly() {
        let html = """
        <p>src="cid:body-text"</p>
        <img data-src="cid:data-src@test">
        <img srcset="cid:srcset@test 1x">
        <a href="cid:link@test">link</a>
        <img src="cid:logo@test">
        <img src='CID:photo%40test'>
        <img src=cid:inline>
        <img src="cid:logo@test">
        """

        #expect(InlineImageHTML.sources(inHTML: html) == [
            "cid:logo@test", "CID:photo%40test", "cid:inline",
        ])
    }

    @Test("body text, other attribute values and non-img tags are never sources")
    func sourcesIgnoreTextAttributesAndOtherTags() {
        let html = """
        <p>hello src="cid:text@test" world</p>
        <p title=" src='cid:title@test'">title</p>
        <img alt=" src='cid:alt@test'">
        <video src="cid:video@test"></video>
        <image src="cid:svg@test"></image>
        <IMG SRC="CID:PHOTO@TEST">
        <img alt="a > b" src="cid:logo@test">
        """

        #expect(InlineImageHTML.sources(inHTML: html) == ["CID:PHOTO@TEST", "cid:logo@test"])
    }

    @Test("rewriting leaves body text, other attributes and non-img tags untouched")
    func replacingIgnoresTextAttributesAndOtherTags() {
        let html = """
        <p>hello src="cid:logo@test" world</p>
        <p title=" src='cid:logo@test'">title</p>
        <img alt=" src='cid:logo@test'">
        <video src="cid:logo@test"></video>
        <image src="cid:logo@test"></image>
        <img alt="a > b" src="cid:logo@test" alt2="logo">
        """
        let replaced = InlineImageHTML.replacingSources(
            inHTML: html,
            with: ["cid:logo@test": "data:image/png;base64,AAA"]
        )

        #expect(replaced == """
        <p>hello src="cid:logo@test" world</p>
        <p title=" src='cid:logo@test'">title</p>
        <img alt=" src='cid:logo@test'">
        <video src="cid:logo@test"></video>
        <image src="cid:logo@test"></image>
        <img alt="a > b" src="data:image/png;base64,AAA" alt2="logo">
        """)
    }

    @Test("an unquoted self-closing src keeps its slash outside the replaced value")
    func selfClosingUnquotedSourceKeepsSlash() {
        let html = "<img src=cid:logo@test/>"

        #expect(InlineImageHTML.sources(inHTML: html) == ["cid:logo@test"])
        #expect(
            InlineImageHTML.replacingSources(
                inHTML: html, with: ["cid:logo@test": "data:image/png;base64,AAA"]
            ) == "<img src=data:image/png;base64,AAA/>"
        )
    }

    @Test("quoted src padding is trimmed for the key while the value is replaced")
    func quotedSourcePaddingUsesTrimmedKey() {
        let html = "<img src=\" cid:logo@test \">"

        #expect(InlineImageHTML.sources(inHTML: html) == ["cid:logo@test"])
        #expect(
            InlineImageHTML.replacingSources(
                inHTML: html, with: ["cid:logo@test": "data:image/png;base64,AAA"]
            ) == "<img src=\"data:image/png;base64,AAA\">"
        )
    }

    @Test("normalization strips the prefix and brackets, decodes and lowercases")
    func normalizationHandlesCasePercentAndBrackets() {
        #expect(InlineImageHTML.normalizedCID("  CID:<Logo@Test>  ") == "logo@test")
        #expect(InlineImageHTML.normalizedCID("cid:photo%40test") == "photo@test")
        #expect(InlineImageHTML.normalizedCID("CID:%3Clogo%40test%3E") == "logo@test")
        #expect(InlineImageHTML.normalizedCID("logo@test") == "logo@test")
    }

    @Test("display name and cid local part both match, one attachment each")
    func matchesDisplayNameAndLocalPart() {
        let html = """
        <img src="cid:logo.png"><img src="cid:photo.jpg@test">
        """

        let matches = InlineImageHTML.matches(inHTML: html, attachments: [logo, photo])

        #expect(matches.map(\.source) == ["cid:logo.png", "cid:photo.jpg@test"])
        #expect(matches.map(\.attachment.fileReference) == ["ref-logo", "ref-photo"])
    }

    @Test("a cid without an extension falls back to the image display-name stem")
    func matchesStemWhenCIDOmitsExtension() {
        let html = """
        <img src="cid:logo@test"><img src="cid:notes@test">
        """
        let notes = Attachment(displayName: "notes.pdf", fileReference: "ref-notes")

        let matches = InlineImageHTML.matches(inHTML: html, attachments: [logo, notes])

        #expect(matches.map(\.attachment.fileReference) == ["ref-logo"])
    }

    @Test("zero or several candidate attachments are skipped")
    func ambiguousReferenceIsIgnored() {
        let html = """
        <img src="cid:logo@test"><img src="cid:missing@test">
        """
        let duplicate = Attachment(displayName: "logo.png", fileReference: "ref-other")

        #expect(InlineImageHTML.matches(inHTML: html, attachments: [logo]).count == 1)
        #expect(InlineImageHTML.matches(inHTML: html, attachments: [logo, duplicate]).isEmpty)
        #expect(InlineImageHTML.matches(inHTML: html, attachments: []).isEmpty)
    }

    @Test("rewriting touches only the replaced src value and keeps the rest byte-for-byte")
    func replacingOnlyTouchesSourceValues() {
        let html = """
        <img src="cid:logo@test" alt="logo">
        <img src='cid:keep@test'>
        <img data-src="cid:logo@test">
        <img srcset="cid:logo@test 1x">
        <a href="cid:logo@test">text cid:logo@test</a>
        <img src="CID:LOGO%40TEST">
        """
        let replaced = InlineImageHTML.replacingSources(
            inHTML: html,
            with: [
                "cid:logo@test": "data:image/png;base64,AAA",
                "CID:LOGO%40TEST": "data:image/png;base64,BBB",
            ]
        )

        #expect(replaced == """
        <img src="data:image/png;base64,AAA" alt="logo">
        <img src='cid:keep@test'>
        <img data-src="cid:logo@test">
        <img srcset="cid:logo@test 1x">
        <a href="cid:logo@test">text cid:logo@test</a>
        <img src="data:image/png;base64,BBB">
        """)
        #expect(InlineImageHTML.replacingSources(inHTML: html, with: [:]) == html)
    }

    @Test("the data URL follows the image magic number and rejects non-images")
    func dataURLSniffsCommonImageFormats() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00])
        let gif = Data("GIF89a".utf8)
        let webp = Data("RIFF".utf8) + Data([0x10, 0x00, 0x00, 0x00]) + Data("WEBP".utf8)
        let bmp = Data("BM".utf8) + Data([0x00, 0x00])
        let tiffLE = Data([0x49, 0x49, 0x2A, 0x00])
        let tiffBE = Data([0x4D, 0x4D, 0x00, 0x2A])
        let heic = Data([0x00, 0x00, 0x00, 0x18]) + Data("ftypheic".utf8)

        #expect(try #require(InlineImageHTML.dataURL(for: png)).hasPrefix("data:image/png;base64,"))
        #expect(try #require(InlineImageHTML.dataURL(for: jpeg)).hasPrefix("data:image/jpeg;base64,"))
        #expect(try #require(InlineImageHTML.dataURL(for: gif)).hasPrefix("data:image/gif;base64,"))
        #expect(try #require(InlineImageHTML.dataURL(for: webp)).hasPrefix("data:image/webp;base64,"))
        #expect(try #require(InlineImageHTML.dataURL(for: bmp)).hasPrefix("data:image/bmp;base64,"))
        #expect(try #require(InlineImageHTML.dataURL(for: tiffLE)).hasPrefix("data:image/tiff;base64,"))
        #expect(try #require(InlineImageHTML.dataURL(for: tiffBE)).hasPrefix("data:image/tiff;base64,"))
        #expect(try #require(InlineImageHTML.dataURL(for: heic)).hasPrefix("data:image/heic;base64,"))
        #expect(InlineImageHTML.dataURL(for: Data("not an image".utf8)) == nil)
        #expect(InlineImageHTML.dataURL(for: Data()) == nil)
        #expect(
            InlineImageHTML.dataURL(for: png)
                == "data:image/png;base64,\(png.base64EncodedString())"
        )
    }
}
