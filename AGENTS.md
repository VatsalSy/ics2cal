# Repository Guidelines

## Project Structure & Module Organization
- `Package.swift`: SPM manifest; product `ics2cal` → target `ICS2Cal`.
- `Sources/ICS2Cal/`: executable sources (`Core/`, `Models/`, `Utils/`, `main.swift`).
- `Tests/ICS2CalTests/`: XCTest target; place fixtures under `Tests/ICS2CalTests/Fixtures/` (e.g., `sample.ics`).
- Built binaries are under `.build/{debug,release}/` and a convenience `ics2cal` may exist at repo root.

## Build, Test, and Development Commands
- Build: `swift build` — compiles all targets.
- Run: `swift run ics2cal list` — lists calendars (triggers macOS permission).
- Inspect: `swift run ics2cal info Tests/ICS2CalTests/Fixtures/test.ics` — prints parsed events.
- Sync (dry): `swift run ics2cal dry-run Tests/ICS2CalTests/Fixtures/test.ics --calendar "MyCal"` — prints plan only.
- Test: `swift test` — runs `ICS2CalTests` (XCTest) and processes `Fixtures`.

## Coding Style & Naming Conventions
- Indentation: 4 spaces; line length ~120.
- Types: `PascalCase`; functions/vars: `lowerCamelCase`; constants: `UPPER_SNAKE` only when bridging env vars.
- File names match primary type (e.g., `ICSParser.swift`).
- Prefer pure functions in `Core/` and small helpers in `Utils/`.
- Formatting: use Xcode defaults; optional: run `swift-format`/`SwiftFormat` locally before PRs.

## Testing Guidelines
- Framework: XCTest. Create files like `ICSParserTests.swift` inside `Tests/ICS2CalTests/`.
- Name tests `test…()` and focus on `Core/` determinism (parsing, planning, fingerprints).
- Fixtures live in `Fixtures/`; keep small, anonymized `.ics` files.
- Aim for high coverage on parsers/planner; add edge cases (time zones, repeats, all‑day).

## Commit & Pull Request Guidelines
- Use clear, imperative commits (e.g., `fix: handle all‑day events`).
- PRs include: what/why, usage examples (`swift run …`), and test notes; link issues when relevant.
- Prohibited in commits/PRs: AI tool signatures/ads, generic titles (e.g., “Update files”), and auto “Co-authored-by” tags.

## Security & Configuration Tips
- Platform: macOS 13+ (per `Package.swift`). EventKit prompts on first access; run `swift run ics2cal list` to grant.
- Never commit private calendars or personal `.ics` data; use sanitized fixtures.

## Agent‑Specific Instructions
- When editing CLI wrappers/scripts, mirror patterns from `@dotfiles/` (start with `@dotfiles/zshrc`) if present.
- For AI instruction updates, edit `CLAUDE.md`. Keep commit messages clean per rules above.

