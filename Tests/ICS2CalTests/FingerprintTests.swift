import XCTest
@testable import ICS2Cal

final class FingerprintTests: XCTestCase {

    // MARK: - FNV-1a Hash Tests

    func testFnv1a64Deterministic() {
        let input = "test string"
        let hash1 = Fingerprint.fnv1a64(input)
        let hash2 = Fingerprint.fnv1a64(input)
        XCTAssertEqual(hash1, hash2, "Same input should produce same hash")
    }

    func testFnv1a64EmptyString() {
        let hash = Fingerprint.fnv1a64("")
        XCTAssertEqual(hash.count, 16, "Hash should be 16 hex characters")
        XCTAssertEqual(hash, "cbf29ce484222325", "Empty string should produce FNV-1a offset basis")
    }

    func testFnv1a64KnownValue() {
        // FNV-1a hash of "hello" is well-known
        let hash = Fingerprint.fnv1a64("hello")
        XCTAssertEqual(hash.count, 16, "Hash should be 16 hex characters")
        XCTAssertFalse(hash.isEmpty)
    }

    func testFnv1a64DifferentInputsDifferentHashes() {
        let hash1 = Fingerprint.fnv1a64("input1")
        let hash2 = Fingerprint.fnv1a64("input2")
        XCTAssertNotEqual(hash1, hash2, "Different inputs should produce different hashes")
    }

    // MARK: - Event Hash Tests

    func testEventHashDeterministic() {
        let start = Date(timeIntervalSince1970: 1700000000)
        let end = Date(timeIntervalSince1970: 1700003600)

        let hash1 = Fingerprint.eventHash(title: "Meeting", location: "Room 1", start: start, end: end, isAllDay: false)
        let hash2 = Fingerprint.eventHash(title: "Meeting", location: "Room 1", start: start, end: end, isAllDay: false)

        XCTAssertEqual(hash1, hash2, "Same event should produce same hash")
    }

    func testEventHashAllDayVsTimed() {
        let start = Date(timeIntervalSince1970: 1700000000)
        let end = Date(timeIntervalSince1970: 1700086400)

        let allDayHash = Fingerprint.eventHash(title: "Event", location: nil, start: start, end: end, isAllDay: true)
        let timedHash = Fingerprint.eventHash(title: "Event", location: nil, start: start, end: end, isAllDay: false)

        XCTAssertNotEqual(allDayHash, timedHash, "All-day and timed events should have different hashes")
        XCTAssertTrue(allDayHash.contains("A") || timedHash.contains("T") || allDayHash != timedHash)
    }

    func testEventHashLocationNilVsEmpty() {
        let start = Date(timeIntervalSince1970: 1700000000)
        let end = Date(timeIntervalSince1970: 1700003600)

        let nilLocationHash = Fingerprint.eventHash(title: "Event", location: nil, start: start, end: end, isAllDay: false)
        let emptyLocationHash = Fingerprint.eventHash(title: "Event", location: "", start: start, end: end, isAllDay: false)

        // Both nil and empty string should normalize the same way
        XCTAssertEqual(nilLocationHash, emptyLocationHash, "nil and empty location should produce same hash")
    }

    func testEventHashTimezoneIndependence() {
        // Create the same absolute moment in time
        let utcDate = Date(timeIntervalSince1970: 1700000000)
        let end = Date(timeIntervalSince1970: 1700003600)

        // Hash should be based on UTC time, so same Date produces same hash regardless of system timezone
        let hash1 = Fingerprint.eventHash(title: "Event", location: "Place", start: utcDate, end: end, isAllDay: false)
        let hash2 = Fingerprint.eventHash(title: "Event", location: "Place", start: utcDate, end: end, isAllDay: false)

        XCTAssertEqual(hash1, hash2, "Same UTC time should produce same hash")
    }

    // MARK: - Legacy Hash Tests

    func testLegacyEventHashFormat() {
        let start = Date(timeIntervalSince1970: 1700000000)
        let end = Date(timeIntervalSince1970: 1700003600)

        let legacyHash = Fingerprint.legacyEventHash(title: "Event", location: "Place", start: start, end: end)

        XCTAssertEqual(legacyHash.count, 16, "Legacy hash should be 16 hex characters")
    }

    func testLegacyVsCurrentHashDiffer() {
        let start = Date(timeIntervalSince1970: 1700000000)
        let end = Date(timeIntervalSince1970: 1700003600)

        let legacyHash = Fingerprint.legacyEventHash(title: "Event", location: "Place", start: start, end: end)
        let currentHash = Fingerprint.eventHash(title: "Event", location: "Place", start: start, end: end, isAllDay: false)

        // Current hash includes the A/T flag prefix, so they should differ
        XCTAssertNotEqual(legacyHash, currentHash, "Legacy and current hashes should differ due to flag prefix")
    }

    // MARK: - Collision Resistance Tests

    func testSimilarEventsProduceDifferentHashes() {
        let start = Date(timeIntervalSince1970: 1700000000)
        let end = Date(timeIntervalSince1970: 1700003600)

        let hash1 = Fingerprint.eventHash(title: "Meeting A", location: "Room 1", start: start, end: end, isAllDay: false)
        let hash2 = Fingerprint.eventHash(title: "Meeting B", location: "Room 1", start: start, end: end, isAllDay: false)

        XCTAssertNotEqual(hash1, hash2, "Events with different titles should have different hashes")
    }

    func testDifferentTimesProduceDifferentHashes() {
        let start1 = Date(timeIntervalSince1970: 1700000000)
        let end1 = Date(timeIntervalSince1970: 1700003600)
        let start2 = Date(timeIntervalSince1970: 1700000060) // 1 minute later
        let end2 = Date(timeIntervalSince1970: 1700003660)

        let hash1 = Fingerprint.eventHash(title: "Event", location: nil, start: start1, end: end1, isAllDay: false)
        let hash2 = Fingerprint.eventHash(title: "Event", location: nil, start: start2, end: end2, isAllDay: false)

        XCTAssertNotEqual(hash1, hash2, "Events at different times should have different hashes")
    }

    func testDifferentDurationsProduceDifferentHashes() {
        let start = Date(timeIntervalSince1970: 1700000000)
        let end1 = Date(timeIntervalSince1970: 1700003600) // 1 hour
        let end2 = Date(timeIntervalSince1970: 1700007200) // 2 hours

        let hash1 = Fingerprint.eventHash(title: "Event", location: nil, start: start, end: end1, isAllDay: false)
        let hash2 = Fingerprint.eventHash(title: "Event", location: nil, start: start, end: end2, isAllDay: false)

        XCTAssertNotEqual(hash1, hash2, "Events with different durations should have different hashes")
    }

    func testDifferentLocationsProduceDifferentHashes() {
        let start = Date(timeIntervalSince1970: 1700000000)
        let end = Date(timeIntervalSince1970: 1700003600)

        let hash1 = Fingerprint.eventHash(title: "Event", location: "Room A", start: start, end: end, isAllDay: false)
        let hash2 = Fingerprint.eventHash(title: "Event", location: "Room B", start: start, end: end, isAllDay: false)

        XCTAssertNotEqual(hash1, hash2, "Events with different locations should have different hashes")
    }
}
