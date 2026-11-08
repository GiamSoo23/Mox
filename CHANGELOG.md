# Changelog

Notable changes to Mox, one section per release. Follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions map to
roadmap milestones (M1 = 0.1.0 … M8 = 1.0.0, see
[docs/ROADMAP.md](docs/ROADMAP.md)). Bugs have their full story in
[docs/BUGS.md](docs/BUGS.md).

## [Unreleased]

### Added
- This changelog and a bug log ([#52](https://github.com/GiamSoo23/Mox/issues/52)).

## [0.3.0] - 2026-11-07 · Backend v2

### Added
- The backend is a Supabase CLI project, and the schema is versioned
  migrations instead of SQL pasted by hand
  ([#6](https://github.com/GiamSoo23/Mox/issues/6)).
- Schema v2 in its own `mox` schema: room for four platforms and several
  devices, multi-file bundles (`kind`, `item_count`), and a schema version
  ([#7](https://github.com/GiamSoo23/Mox/issues/7)).
- pgTAP database tests, run against a throwaway Supabase in Docker on every
  backend PR ([#9](https://github.com/GiamSoo23/Mox/issues/9)).
- `shared/PROTOCOL.md`, the contract for all clients, plus JSON fixtures
  that CI checks against the real schema
  ([#8](https://github.com/GiamSoo23/Mox/issues/8)).

### Changed
- Bucket size cap lowered from 500 MB to 50 MB, the Supabase free plan's
  real limit ([#35](https://github.com/GiamSoo23/Mox/issues/35)).
- v1's anonymous storage access narrowed to v1 file names
  (`current.<ext>`). v1 apps keep working.

### Fixed
- `uploaded_at` is refreshed every time the file is replaced, so Android
  no longer misses a second file with the same extension. Database side;
  confirmation against the live API is pending
  ([#48](https://github.com/GiamSoo23/Mox/issues/48)).

### Security
- v2 data can only be read or written by one dedicated Mox user. The
  anonymous role has no access, so Mox is safe inside a Supabase project
  shared with another app ([#40](https://github.com/GiamSoo23/Mox/issues/40)).

## [0.2.0] - 2026-11-07 · Quality gates and CI

### Added
- SwiftLint (strict) for the macOS app and ktlint for the Android app
  ([#4](https://github.com/GiamSoo23/Mox/issues/4)).
- GitHub Actions: lint and build both apps on every PR, with the debug APK
  kept as a downloadable artifact
  ([#5](https://github.com/GiamSoo23/Mox/issues/5)).

### Changed
- macOS code uses descriptive names instead of one-letter variables, and
  the `CurrentFile` model is camelCase with JSON coding keys.
- Android sources formatted to the Android Studio style, with explicit
  imports.

## [0.1.0] - 2026-11-07 · Baseline and open source

### Added
- Android: tapping the "new file" notification copies the file to the
  clipboard ([#1](https://github.com/GiamSoo23/Mox/issues/1)).
- macOS: files from the phone are also put on the pasteboard, as a file
  and as image data ([#1](https://github.com/GiamSoo23/Mox/issues/1)).
- macOS: launch at login, plus the app icon
  ([#1](https://github.com/GiamSoo23/Mox/issues/1)).
- Architecture docs, the v2 design and the roadmap
  ([#2](https://github.com/GiamSoo23/Mox/issues/2)).
- MIT license and `.editorconfig`
  ([#3](https://github.com/GiamSoo23/Mox/issues/3)).

### Changed
- Repository reorganized into `backend/`, `desktop/macos/` and
  `mobile/android/` ([#3](https://github.com/GiamSoo23/Mox/issues/3)).

### Fixed
- The macOS README said the hotkey was ⌘⇧U. It's ⌘⇧M
  ([#2](https://github.com/GiamSoo23/Mox/issues/2)).

## Before 0.1.0

The original personal version: a macOS menu-bar app and an Android app
sharing one file through Supabase. It was built and used daily before the
project was versioned, so it has no separate entries.

[Unreleased]: https://github.com/GiamSoo23/Mox/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/GiamSoo23/Mox/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/GiamSoo23/Mox/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/GiamSoo23/Mox/releases/tag/v0.1.0
