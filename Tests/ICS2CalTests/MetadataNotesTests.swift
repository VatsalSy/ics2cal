import XCTest
@testable import ICS2Cal

final class MetadataNotesTests: XCTestCase {

    // MARK: - encode() Tests

    func testEncodeWithEmptyNotesNoLeadingNewline() {
        let meta = Meta(hash: "abc123", sources: ["file.ics"], uids: ["uid1"], seen: [:])
        let result = MetadataNotes.encode(meta: meta, into: nil)

        // Should NOT start with a newline
        XCTAssertFalse(result.hasPrefix("\n"), "encode() with nil notes should not produce leading newline")
        XCTAssertTrue(result.hasPrefix("--- ics2cal ---"), "Should start with startMarker")
    }

    func testEncodeWithEmptyStringNotesNoLeadingNewline() {
        let meta = Meta(hash: "abc123", sources: ["file.ics"], uids: ["uid1"], seen: [:])
        let result = MetadataNotes.encode(meta: meta, into: "")

        XCTAssertFalse(result.hasPrefix("\n"), "encode() with empty string should not produce leading newline")
        XCTAssertTrue(result.hasPrefix("--- ics2cal ---"), "Should start with startMarker")
    }

    func testEncodePreservesExistingNotes() {
        let meta = Meta(hash: "abc123", sources: ["file.ics"], uids: ["uid1"], seen: [:])
        let existingNotes = "My important notes here"
        let result = MetadataNotes.encode(meta: meta, into: existingNotes)

        XCTAssertTrue(result.hasPrefix("My important notes here\n"), "Should preserve existing notes at beginning")
        XCTAssertTrue(result.contains("--- ics2cal ---"), "Should contain start marker")
        XCTAssertTrue(result.contains("--- /ics2cal ---"), "Should contain end marker")
    }

    func testEncodeStripsOldMetadataBeforeAddingNew() {
        let meta = Meta(hash: "new123", sources: ["new.ics"], uids: ["new1"], seen: [:])
        let existingNotesWithOldMeta = """
            User notes
            --- ics2cal ---
            {"v":1,"hash":"old","sources":[],"uids":[],"seen":{}}
            --- /ics2cal ---
            """
        let result = MetadataNotes.encode(meta: meta, into: existingNotesWithOldMeta)

        // Count occurrences of markers - should only have one pair
        let startCount = result.components(separatedBy: "--- ics2cal ---").count - 1
        let endCount = result.components(separatedBy: "--- /ics2cal ---").count - 1
        XCTAssertEqual(startCount, 1, "Should have exactly one start marker")
        XCTAssertEqual(endCount, 1, "Should have exactly one end marker")
        XCTAssertTrue(result.contains("new123"), "Should contain new hash")
    }

    // MARK: - decode() Tests

    func testDecodeValidMetadata() {
        let notes = """
            User notes
            --- ics2cal ---
            {"v":1,"hash":"abc123","sources":["file.ics"],"uids":["uid1"],"seen":{}}
            --- /ics2cal ---
            """
        let meta = MetadataNotes.decode(from: notes)

        XCTAssertNotNil(meta, "Should decode valid metadata")
        XCTAssertEqual(meta?.hash, "abc123")
        XCTAssertEqual(meta?.sources, ["file.ics"])
        XCTAssertEqual(meta?.uids, ["uid1"])
    }

    func testDecodeFromNilReturnsNil() {
        let meta = MetadataNotes.decode(from: nil)
        XCTAssertNil(meta, "decode() with nil input should return nil")
    }

    func testDecodeMissingMarkersReturnsNil() {
        let notes = "Just some user notes without any metadata"
        let meta = MetadataNotes.decode(from: notes)
        XCTAssertNil(meta, "decode() with no markers should return nil")
    }

    func testDecodeMissingEndMarkerReturnsNil() {
        let notes = """
            --- ics2cal ---
            {"v":1,"hash":"abc123","sources":[],"uids":[],"seen":{}}
            """
        let meta = MetadataNotes.decode(from: notes)
        XCTAssertNil(meta, "decode() with missing end marker should return nil")
    }

    func testDecodeMissingStartMarkerReturnsNil() {
        let notes = """
            {"v":1,"hash":"abc123","sources":[],"uids":[],"seen":{}}
            --- /ics2cal ---
            """
        let meta = MetadataNotes.decode(from: notes)
        XCTAssertNil(meta, "decode() with missing start marker should return nil")
    }

    func testDecodeBadJSONReturnsNil() {
        let notes = """
            --- ics2cal ---
            {invalid json here}
            --- /ics2cal ---
            """
        let meta = MetadataNotes.decode(from: notes)
        XCTAssertNil(meta, "decode() with invalid JSON should return nil")
    }

    func testDecodeEndMarkerBeforeStartMarkerReturnsNil() {
        // This tests the fix: endMarker should only be found AFTER startMarker
        let notes = """
            --- /ics2cal ---
            Some text
            --- ics2cal ---
            {"v":1,"hash":"abc","sources":[],"uids":[],"seen":{}}
            """
        let meta = MetadataNotes.decode(from: notes)
        XCTAssertNil(meta, "decode() with end marker before start marker should return nil")
    }

    func testDecodeMultipleMetadataBlocksUsesFirst() {
        let notes = """
            --- ics2cal ---
            {"v":1,"hash":"first","sources":[],"uids":[],"seen":{}}
            --- /ics2cal ---
            --- ics2cal ---
            {"v":1,"hash":"second","sources":[],"uids":[],"seen":{}}
            --- /ics2cal ---
            """
        let meta = MetadataNotes.decode(from: notes)

        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.hash, "first", "Should decode the first metadata block")
    }

    // MARK: - strip() Tests

    func testStripRemovesMetadata() {
        let notes = """
            User notes before
            --- ics2cal ---
            {"v":1,"hash":"abc","sources":[],"uids":[],"seen":{}}
            --- /ics2cal ---
            """
        let result = MetadataNotes.strip(notes)

        XCTAssertFalse(result.contains("--- ics2cal ---"), "Should remove start marker")
        XCTAssertFalse(result.contains("--- /ics2cal ---"), "Should remove end marker")
        XCTAssertFalse(result.contains("hash"), "Should remove JSON content")
        XCTAssertEqual(result, "User notes before", "Should preserve user notes")
    }

    func testStripNoMetadataReturnsOriginal() {
        let notes = "Just user notes without metadata"
        let result = MetadataNotes.strip(notes)
        XCTAssertEqual(result, notes, "strip() with no metadata should return original")
    }

    func testStripMissingEndMarkerReturnsOriginal() {
        let notes = """
            User notes
            --- ics2cal ---
            {"v":1,"hash":"abc","sources":[],"uids":[],"seen":{}}
            """
        let result = MetadataNotes.strip(notes)
        XCTAssertTrue(result.contains("--- ics2cal ---"), "Should not remove partial metadata")
    }

    func testStripEndMarkerBeforeStartMarkerReturnsOriginal() {
        // This tests the fix: endMarker lookup should only search after startMarker
        let notes = """
            --- /ics2cal ---
            Some text
            --- ics2cal ---
            {"v":1,"hash":"abc","sources":[],"uids":[],"seen":{}}
            """
        let result = MetadataNotes.strip(notes)
        XCTAssertTrue(result.contains("--- ics2cal ---"), "Should not remove when end is before start")
        XCTAssertTrue(result.contains("--- /ics2cal ---"), "Should preserve both markers")
    }

    func testStripMultipleMetadataBlocksRemovesFirst() {
        let notes = """
            User notes
            --- ics2cal ---
            {"v":1,"hash":"first","sources":[],"uids":[],"seen":{}}
            --- /ics2cal ---
            More notes
            --- ics2cal ---
            {"v":1,"hash":"second","sources":[],"uids":[],"seen":{}}
            --- /ics2cal ---
            """
        let result = MetadataNotes.strip(notes)

        // First block should be removed
        XCTAssertFalse(result.contains("first"), "Should remove first metadata block")
        XCTAssertTrue(result.contains("User notes"), "Should preserve user notes before")
        XCTAssertTrue(result.contains("More notes"), "Should preserve user notes between")
        // Second block may or may not be present depending on implementation
    }

    func testStripPreservesWhitespaceInsideUserNotes() {
        let notes = """
            Line 1
            Line 2

            Line 4 after blank
            --- ics2cal ---
            {"v":1,"hash":"abc","sources":[],"uids":[],"seen":{}}
            --- /ics2cal ---
            """
        let result = MetadataNotes.strip(notes)

        XCTAssertTrue(result.contains("Line 1"))
        XCTAssertTrue(result.contains("Line 2\n\nLine 4 after blank"), "Should preserve internal blank line between user notes")
    }

    // MARK: - Round-trip Tests

    func testEncodeDecodeRoundTrip() {
        let originalMeta = Meta(hash: "roundtrip", sources: ["a.ics", "b.ics"], uids: ["u1", "u2"], seen: ["a.ics": "2025-01-01T00:00:00Z"])
        let encoded = MetadataNotes.encode(meta: originalMeta, into: "User notes")
        let decoded = MetadataNotes.decode(from: encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.hash, originalMeta.hash)
        XCTAssertEqual(decoded?.sources, originalMeta.sources)
        XCTAssertEqual(decoded?.uids, originalMeta.uids)
        XCTAssertEqual(decoded?.seen, originalMeta.seen)
    }

    func testStripAfterEncodeRestoresOriginalNotes() {
        let originalNotes = "My important notes"
        let meta = Meta(hash: "test", sources: [], uids: [], seen: [:])
        let encoded = MetadataNotes.encode(meta: meta, into: originalNotes)
        let stripped = MetadataNotes.strip(encoded)

        XCTAssertEqual(stripped, originalNotes, "strip(encode(notes)) should return original notes")
    }
}
