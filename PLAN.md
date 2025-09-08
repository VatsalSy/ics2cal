# ICS to Apple Calendar Sync Tool - Implementation Plan

## Project Overview
A Swift-based command-line tool that intelligently synchronizes events from ICS (iCalendar) files to Apple Calendar, with sophisticated duplicate detection to prevent creating redundant events.

## Problem Statement
When importing events from ICS files (e.g., seminar schedules, conference programs), users often face:
- Duplicate events when re-importing updated schedules
- Manual checking of existing calendar entries
- No intelligent matching of events that may have slight variations
- Difficulty managing recurring academic/professional events

## Solution Architecture

### Core Principle (Updated)
Deterministic, source-aware mirror sync with stable identities:
1. **Identity Precedence**: Prefer ICS `UID` when present; otherwise use a stable fingerprint.
2. **Stable Fingerprint**: Hash of normalized `(start_utc_minute | duration_min | title | location)`.
3. **Source-Aware Mirror**: Track which source(s) created/own an event; safely delete only when no sources still reference it.
4. **Fuzzy Adoption (Optional)**: Use time ±N minutes and normalized title/location to adopt pre-existing events, but never as primary identity over UID/hash.

### Technology Stack
- **Language**: Swift 5.9+
- **Framework**: EventKit (Apple Calendar API)
- **CLI Framework**: Built-in Foundation (zero external dependencies)
- **Package Manager**: Swift Package Manager (SPM)
- **Testing**: XCTest

## Detailed Project Structure

```
scripts/
├── ics2cal                           # Executable wrapper script
│   # - Checks for Swift availability
│   # - Builds package if needed
│   # - Executes compiled binary
│   # - Handles environment setup
│
└── ics2cal_cli/                      # Swift Package
    ├── Package.swift                 # SPM manifest
    │
    ├── Sources/
    │   └── ICS2Cal/
    │       ├── main.swift            # CLI entry point
    │       │   # - Minimal argument parsing (Foundation)
    │       │   # - Command routing
    │       │   # - Exit code handling
    │       │
    │       ├── Commands/
    │       │   ├── SyncCommand.swift     # Main sync operation
    │       │   ├── DryRunCommand.swift   # Preview without changes
    │       │   ├── ListCommand.swift     # List available calendars
    │       │   └── InfoCommand.swift     # Show event details
    │       │
    │       ├── Core/
    │       │   ├── ICSParser.swift       # ICS file parsing (VEVENT-only)
    │       │   │   # - VEVENT extraction
    │       │   │   # - Property unfolding
    │       │   │   # - DTSTART/DTEND parsing with TZID or Z
    │       │   │
    │       │   ├── CalendarSync.swift    # EventKit integration (scaffold)
    │       │   │   # - Permission management
    │       │   │   # - Event CRUD operations
    │       │   │   # - Calendar enumeration
    │       │   │   # - Batch operations
    │       │   │
    │       │   └── EventMatcher.swift    # Identity & adoption
    │       │       # - UID precedence
    │       │       # - Stable fingerprint
    │       │       # - Optional fuzzy adoption (time ±N, text sim)
    │       │
    │       ├── Models/
    │       │   ├── Event.swift           # Event data model
    │       │   │   # Properties:
    │       │   │   # - uid: String?
    │       │   │   # - title: String
    │       │   │   # - location: String?
    │       │   │   # - startDate: Date
    │       │   │   # - endDate: Date
    │       │   │   # - description: String?
    │       │   │   # - url: URL?
    │       │   │   # - categories: [String]
    │       │   │   # - status: EventStatus
    │       │   │   # - recurrenceRule: RecurrenceRule?
    │       │   │
    │       │   ├── Calendar.swift        # Calendar wrapper
    │       │   ├── MatchResult.swift     # Matching results
    │       │   └── SyncReport.swift      # Sync operation report
    │       │
    │       └── Utils/
    │           ├── DateHelper.swift      # Date/timezone utilities
    │           ├── Logger.swift          # Logging system
    │           ├── TextNormalize.swift   # Normalization & diacritics folding
    │           ├── Fingerprint.swift     # FNV-1a 64-bit hash
    │           ├── Metadata.swift        # Notes-embedded JSON metadata
    │           └── Permissions.swift     # EventKit permissions
    │
    └── Tests/
        └── ICS2CalTests/
            ├── ICSParserTests.swift
            ├── EventMatcherTests.swift
            ├── DateHelperTests.swift
            └── Fixtures/
                ├── sample.ics
                ├── recurring.ics
                └── timezone.ics
```

## Component Specifications

### 1. ICS Parser Component (Simplified Scope)

#### Responsibilities
- Parse ICS files according to RFC 5545 (subset)
- Handle multi-line property unfolding
- Extract and validate VEVENT components
- Parse DTSTART/DTEND (support TZID parameter and trailing Z)
- Scope: VEVENT-only; no RRULE/EXDATE/RECURRENCE-ID

#### Key Methods
```swift
class ICSParser {
    func parse(fileURL: URL) throws -> [Event]
    func parseVEvent(_ lines: [String]) throws -> Event
    func parseDateTime(_ value: String, tzid: String?) -> Date
    func unfoldLines(_ content: String) -> [String]
}
```

#### Parsing Rules
- Handle line folding (lines starting with space/tab)
- Support quoted-printable and base64 encodings (best-effort)
- Parse parameters (at least TZID, VALUE)
- Validate required properties (DTSTART and DTEND or DURATION)

### 2. Calendar Sync Component

#### Responsibilities
- Request and manage EventKit permissions
- Enumerate available calendars
- Create, update, and query events
- Handle batch operations efficiently
- Manage sync state

#### Key Methods
```swift
class CalendarSync {
    func requestAccess() async throws -> Bool
    func listCalendars() -> [EKCalendar]
    func findCalendar(named: String) -> EKCalendar?
    func getEvents(in calendar: EKCalendar, 
                   from: Date, to: Date) -> [EKEvent]
    func createEvent(_ event: Event, 
                     in calendar: EKCalendar) throws
    func updateEvent(_ existing: EKEvent, 
                     with event: Event) throws
}
```

#### Permission Handling
- Check current authorization status
- Request access if needed
- Provide clear error messages
- Support privacy settings URL

### 3. Identity, Matching, and Mirror

#### Responsibilities
- Establish a deterministic identity for each event.
- Adopt existing events when appropriate without producing duplicates.
- Implement safe mirror deletions scoped to a `source` label.

#### Identity and Fingerprint
- Primary identity: ICS `UID` if present (UID set maintained in metadata).
- Stable fingerprint: FNV-1a 64-bit over `start_utc_minute | duration_min | norm(title) | norm(location)`.
- Normalization: trim, collapse whitespace, lowercase, diacritic/punctuation folding, drop common prefixes (e.g., "seminar:").

#### Matching Order
1. Match by metadata `hash` (fingerprint) → update in place.
2. Match by any stored `UID` → update in place; add new UID if different.
3. Optional fuzzy adoption: time ±N minutes plus normalized title/location similarity.
4. Otherwise create a new event.

#### Source-Aware Mirror Semantics
- Each sync run supplies `--source <id>` when `--mirror` is used.
- At the end of a run: remove the `source` tag from events not present in the input. If no sources remain on an event, delete it.
- Prevents deleting events that another source still references.

### 4. CLI Interface

### Notes-Embedded Metadata

- Store a compact JSON block inside `EKEvent.notes` between clear markers to retain user notes and avoid external storage.
- Example block (appended to notes):
  ```
  --- ics2cal ---
  {"v":1,"hash":"ab12cd34ef...","sources":["seminars-2025","dept-feed"],
   "uids":["A@x","B@y"],"seen":{"seminars-2025":"2025-09-08T12:34:56Z"}}
  --- /ics2cal ---
  ```
  - `v`: schema version; `hash`: fingerprint; `sources`: owning sources; `uids`: known UIDs; `seen`: last-seen timestamps.

#### Commands

##### `sync` - Main synchronization
```bash
ics2cal sync <ics-file> --calendar <name> [options]

Options:
  --calendar, -c     Target calendar name (required)
  --source, -S       Source identifier for this run (required with --mirror)
  --mirror           Enable source-aware mirror deletes
  --adopt-existing   Allow fuzzy adoption of pre-existing events
  --time-window      Fuzzy adoption window in minutes (default: 5)
  --from DATE        Only scan/update from DATE (YYYY-MM-DD)
  --to DATE          Only scan/update until DATE (YYYY-MM-DD)
  --add-only         Do not update/delete existing events
  --json             Machine-readable output
  --yes, -y          Assume yes to prompts
  --no-color         Disable colored output
  --verbose, -v      Enable verbose logging
  --dry-run          Preview without making changes
```

##### `list` - Show available calendars
```bash
ics2cal list [options]

Options:
  --format    Output format [table|json|names]
  --writable  Show only writable calendars
```

##### `dry-run` - Preview sync operation
```bash
ics2cal dry-run <ics-file> --calendar <name> [options]

# Shows:
# - Events to be added/updated/deleted (by source)
# - Fingerprints and UID matches
# - Fuzzy-adopt candidates with scores
```

##### `info` - Show ICS file details
```bash
ics2cal info <ics-file> [options]

Options:
  --format     Output format [summary|detailed|json]
  --validate   Validate ICS structure
```

### 5. Data Models

#### Event Model
```swift
struct Event {
    // Required fields
    let uid: String?
    let title: String
    let startDate: Date
    let endDate: Date
    
    // Optional fields
    let location: String?
    let description: String?
    let url: URL?
    let organizer: String?
    let attendees: [String]
    let categories: [String]
    let status: EventStatus
    
    // Metadata
    let created: Date?
    let lastModified: Date?
    let sequence: Int
    // Derived identity
    let fingerprint: String
}

enum EventStatus: String {
    case confirmed = "CONFIRMED"
    case tentative = "TENTATIVE"
    case cancelled = "CANCELLED"
}
```

#### Sync Report Model
```swift
struct SyncReport {
    let startTime: Date
    let endTime: Date
    let calendar: String
    
    let eventsProcessed: Int
    let eventsAdded: Int
    let eventsSkipped: Int
    let eventsUpdated: Int
    
    let duplicates: [DuplicateEntry]
    let errors: [SyncError]
    
    struct DuplicateEntry {
        let icsEvent: Event
        let existingEvent: EKEvent
        let confidence: Double
        let matchedFields: Set<MatchField>
    }
}
```

## Implementation Phases

### Phase 1: Foundation (Week 1)
- [ ] Set up Swift package (zero deps)
- [ ] VEVENT-only parser + unfolding + TZID/Z handling
- [ ] Event model + `fingerprint` computation
- [ ] Notes metadata encode/decode helpers
- [ ] Basic CLI (`info`, `list`, `sync --add-only`)

### Phase 2: Mirror & Metadata (Week 2)
- [ ] `--source` and `--mirror` semantics (source-scoped deletes)
- [ ] EventKit integration: list calendars, add/update events
- [ ] Persist metadata in `EKEvent.notes`
- [ ] Date window flags (`--from/--to`)

### Phase 3: Adoption & UX (Week 3)
- [ ] Fuzzy adoption (time ±N, normalized title/location)
- [ ] Tunables: `--time-window`, `--adopt-existing`
- [ ] JSON output, `--yes`, `--no-color`, logging polish

### Phase 4: Testing & Perf (Week 4)
- [ ] Unit + integration tests with fixtures
- [ ] Performance passes and batching
- [ ] Documentation and examples

## Usage Examples

### Basic Sync
```bash
# Sync seminars to Work calendar
./ics2cal sync seminars.ics --calendar "Work"

# Output:
# 🔍 Parsing seminars.ics... found 18 events
# 📅 Checking "Work" calendar for existing events...
# ✅ Added: 3 new events
# ⏭️  Skipped: 15 events (already exist)
# 📊 Sync completed in 1.2s
```

### Dry Run with Verbose Output
```bash
./ics2cal dry-run conference.ics --calendar "Conferences" --adopt-existing --time-window 10 --verbose

# Output:
# 🔍 Parsing conference.ics...
# 
# Would ADD:
#   • "Keynote: Future of AI" - Jan 15, 9:00 AM
#   • "Workshop: Swift Development" - Jan 15, 2:00 PM
# 
# Would ADOPT (existing event matches within ±10 minutes):
#   • "Opening Reception" - Jan 14, 6:00 PM (hash: ab12...)
```

### Mirror and Adoption
```bash
# Mirror a specific source (safe deletions scoped to that source)
./ics2cal sync seminars-2025.ics \
  --calendar "Work" \
  --source seminars-2025 \
  --mirror

# Allow adoption of close matches within ±10 minutes
./ics2cal sync dept-feed.ics \
  --calendar "Work" \
  --source dept-feed \
  --adopt-existing \
  --time-window 10
```

## Error Handling

### Common Errors
1. **Permission Denied**
   - Clear message about calendar access
   - Link to System Preferences
   - Suggest running with proper permissions

2. **Calendar Not Found**
   - List available calendars
   - Suggest similar names
   - Option to create new calendar

3. **Invalid ICS Format**
   - Show line number and error
   - Validate against RFC 5545
   - Suggest fixes for common issues

4. **Network Calendar Issues**
   - Handle iCloud sync delays
   - Retry logic for temporary failures
   - Offline mode support

## Testing Strategy

### Unit Tests
- ICS parser: VEVENT-only, folding, TZID/Z, date-only
- Fingerprint stability across whitespace/diacritics/punctuation
- Metadata encode/decode round-trips in notes
- Fuzzy adoption and time-window handling

### Integration Tests
- Add-only sync creates expected events
- Mirror deletes only when a source no longer references an event
- Adoption: ±5–15 minute shifts and minor title changes
- Permission handling and calendar enumeration

### Test Fixtures
- Valid ICS files (basic, varied TZID, date-only)
- Invalid ICS files (malformed, missing fields)
- Edge cases (DST transitions, leap years)
- Large files (performance testing)

## Performance Considerations

### Optimization Strategies
1. **Batch Operations**
   - Load all existing events once
   - Process matches in memory
   - Commit changes in batches

2. **Smart Caching**
   - Cache calendar list
   - Store parsed timezone data
   - Remember permission status

3. **Efficient Matching**
   - Index events by date range
   - Early exit on high confidence
   - Parallel processing for large files

### Benchmarks
- Target: <1s for 100 events
- Memory: <50MB for typical use
- Support files up to 10,000 events

## Security & Privacy

### Considerations
- Request minimal permissions
- Don't store calendar data
- Clear event data after sync
- Support audit logging
- Handle sensitive information properly

### Privacy Features
- No network requests (local only)
- No data collection
- Optional logging (off by default)
- Secure credential handling

## Distribution

### Build Process
```bash
# Build for current architecture
swift build -c release

# Build universal binary
swift build -c release --arch arm64 --arch x86_64

# Create distributable
./package.sh
```

### Installation Methods
1. **Direct Download**
   - Provide signed binary
   - Include man page
   - Shell completion scripts

2. **Homebrew Formula** (future)
   ```ruby
   class Ics2cal < Formula
     desc "Sync ICS files to Apple Calendar"
     homepage "https://github.com/user/ics2cal"
     url "..."
     sha256 "..."
     
     depends_on xcode: ["14.0", :build]
     
     def install
       system "swift", "build", "-c", "release"
       bin.install ".build/release/ics2cal"
     end
   end
   ```

## Future Enhancements

### Version 2.0
- [ ] Two-way sync support
- [ ] Multiple calendar targets
- [ ] Event modification detection
- [ ] Conflict resolution UI

### Version 3.0
- [ ] CalDAV server support
- [ ] Google Calendar integration
- [ ] Web interface
- [ ] Sync scheduling/automation

## Success Criteria

### Functional Requirements
- ✅ Parse standard ICS VEVENTs correctly
- ✅ Deterministic identity (UID/fingerprint)
- ✅ Source-aware mirror deletes
- ✅ Detect duplicates with >95% accuracy
- ✅ Handle timezone conversions properly (TZID/Z)

### Non-Functional Requirements
- ✅ Process 100 events in <1 second
- ✅ Memory usage <50MB
- ✅ Clear error messages
- ✅ Comprehensive logging
- ✅ 90% test coverage

## Development Guidelines

### Code Style
- Swift standard library conventions
- Clear, descriptive naming
- Comprehensive documentation
- Error handling with Result types
- Async/await for EventKit operations

### Architecture Principles
- Separation of concerns
- Dependency injection
- Protocol-oriented design
- Testable components
- Minimal external dependencies

## Conclusion

This tool will provide a robust, intelligent solution for synchronizing ICS calendar files with Apple Calendar, eliminating the frustration of duplicate events while maintaining data integrity. The phased implementation approach ensures steady progress with regular deliverables, while the comprehensive testing strategy guarantees reliability.

The smart matching algorithms and flexible configuration options make this tool suitable for various use cases, from academic seminars to corporate meetings, providing users with confidence that their calendar remains organized and duplicate-free.
