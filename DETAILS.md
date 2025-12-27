# ics2cal — Implementation Details

This document describes how ics2cal parses ICS files, matches them to Apple Calendar events, and applies sync operations.

## Architecture Overview

- CLI entry: `Sources/ICS2Cal/main.swift`
- Core:
  - `ICSParser`: VEVENT‑only, with line unfolding, TZID/Z datetime parsing
  - `CalendarSync`: EventKit integration (list/query/create/update/delete)
  - `SyncPlanner`: computes add/update/delete plan using identity + metadata
- Utilities:
  - `TextNormalize`, `Fingerprint`, `Metadata`

## Event Identity

1. Prefer ICS `UID` when available.
2. Otherwise compute a stable fingerprint: FNV‑1a 64‑bit over
   `start_utc_minute | duration_minutes | norm(title) | norm(location)`.
3. Normalization trims, collapses whitespace, folds case/diacritics, removes punctuation, and drops common prefixes like `seminar:`.

## Metadata in Notes

To avoid external state, we embed a compact JSON block inside `EKEvent.notes`:

```text
--- ics2cal ---
{"v":1,"hash":"<fingerprint>","sources":["<id>"],"uids":["<ics-uid>"],"seen":{"<id>":"2025-09-08T12:34:56Z"}}
--- /ics2cal ---
```

Fields:

- `hash`: current fingerprint of the event
- `sources`: source IDs that "own" this event (for mirror deletes)
- `uids`: known ICS UIDs associated with this event
- `seen`: last‑seen timestamps per source

The helpers in `Metadata.swift` append/strip/parse this block while preserving any user notes outside the markers.

## Matching and Planning

Given parsed ICS events and a target calendar:

1. Load existing EKEvents in a date window (expanded by ±`--time-window` for adoption).
2. Index existing by metadata `hash` and by stored `uids`.
3. For each ICS event:
   - UID match → update if title/location/time changed or if we need to attach missing `source`.
   - Hash match → same as above.
   - If `--adopt-existing` → fuzzy adoption when:
     - normalized title equal AND
     - normalized location equal (or one side empty) AND
     - start and duration within ±`--time-window` minutes.
     Adopted events are updated and get metadata attached.
   - Otherwise → plan Add.
4. If `--mirror --source <id>`:
   - For existing events that list `<id>` in `sources` but whose `hash` is not present in the incoming set:
     - If removing `<id>` leaves `sources` empty → plan Delete.
     - Otherwise → update metadata to remove the source (detach only).

`--add-only` disables updates and deletes (adds still occur).

## Parser Notes (ICSParser)

- VEVENT only (no RRULE/EXDATE/RECURRENCE‑ID in current scope).
- Handles RFC5545 line folding (space/tab‑prefixed continuation lines).
- Parses DTSTART/DTEND with optional TZID or trailing `Z` (UTC).
- If DTEND missing, a 1‑hour default duration is applied.

## EventKit Integration (CalendarSync)

- `listCalendars()`—enumerates calendars for `.event`.
- `events(in:from:to:)`—queries events via EventKit predicate.
- `createEvent/updateEvent/removeEvent`—apply changes and persist metadata.

## CLI Commands

- `info <ics>` — count and summarize events.
- `list` — print calendars; also triggers the macOS permission prompt.
- `dry-run <ics> --calendar <name>` — print planned counts only.
- `sync <ics> --calendar <name>` — apply adds/updates/deletes.

Key flags:

- `--source <id>` and `--mirror` for source‑scoped mirror semantics.
- `--adopt-existing` and `--time-window <min>` for fuzzy adoption (default 5).
- `--from/--to` to bound the query window; otherwise a heuristic is derived from the ICS file (30 days before min start, to 365 days after max end).
- `--add-only` to only insert new events.

## Limitations and Future Work

- Recurrence rules (RRULE/EXDATE) are not yet supported.
- No two‑way sync; i.e., tool does not export changes back to ICS.
- Adoption strategy is conservative to avoid false positives.
- JSON/verbose output for per‑item plans can be added.

## Performance Considerations

- Batch query existing events once per run.
- Use in‑memory maps for quick lookups by UID and hash.
- Target: ~100 events in <1s on typical hardware.
