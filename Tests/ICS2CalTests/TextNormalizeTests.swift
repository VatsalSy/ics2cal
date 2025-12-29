import XCTest
@testable import ICS2Cal

final class TextNormalizeTests: XCTestCase {

    func testNormCaseFoldingAndDiacritics() {
        let raw = "Cafe\u{0301} TALK"
        let normalized = TextNormalize.norm(raw)

        XCTAssertEqual(normalized, "cafe talk")
    }

    func testNormDropsKnownPrefixesBeforePunctuationRemoval() {
        let raw = "Talk:   GraphQL 101"
        let normalized = TextNormalize.norm(raw)

        XCTAssertEqual(normalized, "graphql 101")
    }

    func testNormStripsPunctuationAndCollapsesWhitespace() {
        let raw = " Hello,  world!  (v2)\n-- great "
        let normalized = TextNormalize.norm(raw)

        XCTAssertEqual(normalized, "hello world v2 great")
    }

    func testNormCollapsesNewlinesAfterPrefixDrop() {
        let raw = "Seminar:  Line one\nLine two\tLine three"
        let normalized = TextNormalize.norm(raw)

        XCTAssertEqual(normalized, "line one line two line three")
    }
}
