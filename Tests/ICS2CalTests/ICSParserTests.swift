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
        XCTAssertFalse(events[0].isAllDay)
    }

    func testParsesAllDayFixtureWithEscapes() throws {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "all_day", withExtension: "ics") else {
            XCTFail("Missing fixture 'all_day.ics'")
            return
        }
        let parser = ICSParser()
        let events = try parser.parse(fileURL: url)
        XCTAssertEqual(events.count, 1)
        let event = events[0]
        XCTAssertTrue(event.isAllDay)
        XCTAssertEqual(event.title, "All-Day Retreat")
        XCTAssertEqual(event.location, "Hillside Lodge, Room A")
        XCTAssertEqual(event.organizer, "CN=Support;Desk:mailto:support@example.com")
        XCTAssertTrue(event.description?.contains("First line") ?? false)
        XCTAssertTrue(event.description?.contains("\n second line") ?? false)
        XCTAssertTrue(event.description?.contains("literal comma, and semicolon; plus newline") ?? false)
        XCTAssertTrue(event.description?.contains("newline\nend.") ?? false)
        XCTAssertTrue(event.description?.contains("Path C:\\Temp") ?? false)
        XCTAssertEqual(event.endDate.timeIntervalSince(event.startDate), 2 * 24 * 60 * 60, accuracy: 1)
    }
}
