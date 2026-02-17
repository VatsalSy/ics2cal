> [!WARNING]
> **Deprecated:** `ics2cal` is deprecated and will be archived.
> Please use [`calcli`](https://github.com/VatsalSy/calcli) instead.

# ics2cal

Sync ICS (.ics) files to Apple Calendar on macOS with duplicate‑safe matching, dry runs, and optional mirror deletes.

## Features
- Deterministic matching using ICS `UID` and a stable fingerprint (title/location/time)
- Dry‑run previews before applying changes
- Optional source‑aware mirror deletes (`--mirror --source <id>`)
- Minimal dependencies (uses EventKit only)

## Requirements
- macOS 13 or newer
- Xcode/Swift 5.9+ (for building)
- Calendar access permission (EventKit prompts on first run)

## Installation

- Quick install (release build):
  - `chmod +x install.sh`
  - `./install.sh` (uses `/usr/local/bin` by default; `--user` installs to `$HOME/bin`)

- Manual build:
  - `swift build -c release`
  - Copy `.build/release/ics2cal` somewhere on your `PATH`

## Usage

- List calendars (grants permission if needed):
  - `ics2cal list`

- Inspect an ICS file:
  - `ics2cal info path/to/file.ics`

- Dry‑run a sync:
  - `ics2cal dry-run path/to/file.ics --calendar "MyCal"`

- Apply a sync:
  - `ics2cal sync path/to/file.ics --calendar "MyCal"`

- Mirror deletes scoped to a source:
  - `ics2cal sync path/to/file.ics --calendar "MyCal" --source dept-feed --mirror`

Common options:
- `--adopt-existing` enable conservative fuzzy adoption (time ±N minutes; title/location normalized)
- `--time-window <min>` adoption window (default: 5)
- `--from YYYY-MM-DD` / `--to YYYY-MM-DD` limit scanned range
- `--add-only` never update/delete existing events

Notes:
- If you see “Calendar access not authorized”, run `ics2cal list` once and approve access.

## Documentation
- Implementation details: see `DETAILS.md`.
- Changelog: see `CHANGELOG.md`.

## Contributing
Please read `CONTRIBUTING.md` for development flow, code style, and commit/PR guidelines.

## Code of Conduct
Be kind and respectful. See `CODE_OF_CONDUCT.md`.

## Security
Report vulnerabilities as described in `SECURITY.md`.

## License
MIT — see `LICENSE` for details.
