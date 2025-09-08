# Contributing to ics2cal

Thanks for your interest in contributing! This project welcomes bug reports, fixes, features, and documentation improvements.

## Getting Started
- Requirements: macOS 13+, Xcode/Swift 5.9+
- Build: `swift build`
- Run: `swift run ics2cal --help`
- Tests: `swift test`

## Development Workflow
1. Fork and create a feature branch.
2. Make focused changes with clear commits.
3. Run `swift test` and ensure `swift build` is clean.
4. Open a PR describing what and why; add usage examples if relevant.

## Code Style
- Swift naming and structure; keep changes minimal and focused.
- Indentation: 4 spaces; line length ~120.
- Types in `Core/` should be as pure/deterministic as possible; helpers in `Utils/`.
- File names match primary type (e.g., `ICSParser.swift`).

## Commit Messages & PRs
- Use clear, imperative messages (e.g., `fix: handle all‑day events`).
- Avoid generic subjects like “update files”.
- Do not include AI tool signatures, ads, or co‑authored‑by tags from tools.

## Testing
- Unit tests live in `Tests/ICS2CalTests/`.
- Add fixtures under `Tests/ICS2CalTests/Fixtures/`.
- Focus on deterministic logic (parsing, planning, fingerprints). Keep fixtures anonymized.

## Feature Ideas
- RRULE/EXDATE support
- Per‑item verbose/JSON planning output
- Additional adoption strategies and tunables

## Releasing
- Update `CHANGELOG.md`.
- Tag a semantic version (e.g., `v0.2.0`).

## Code of Conduct
Please follow our `CODE_OF_CONDUCT.md`.

