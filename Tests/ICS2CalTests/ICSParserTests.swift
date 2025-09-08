import XCTest
@testable import ICS2Cal

final class ICSParserTests: XCTestCase {
    func testParsesSampleICS() throws {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "sample", withExtension: "ics") else {
            XCTFail("Missing fixture 'sample.ics'")
            return
        }
        let parser = ICSParser()
        let events = try parser.parse(fileURL: url)
        XCTAssertGreaterThan(events.count, 0, "Expected at least one event parsed")
        XCTAssertFalse(events[0].fingerprint.isEmpty)
    }
}

