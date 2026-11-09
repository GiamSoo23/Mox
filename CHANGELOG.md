# Changelog

Notable changes to Mox, one section per release. Follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions map to
roadmap milestones (M1 = 0.1.0 … M8 = 1.0.0, see
[docs/ROADMAP.md](docs/ROADMAP.md)). Bugs have their full story in
[docs/BUGS.md](docs/BUGS.md).

## [Unreleased]

### Added
- **Setup window on the Mac.** With no settings, Mox opens a window that
  signs in to Supabase (or takes an access token), recommends a new project
  or an existing one at the free plan's limit, warns when other people
  manage the project, sets it up, and ends on the pairing QR
  ([#81](https://github.com/GiamSoo23/Mox/issues/81)).

## [0.5.0] - 2026-11-08 · QR pairing

First pre-release with downloadable apps.

### Added
- **Pairing by QR code.** The Mac shows "Pair a Phone…" with a QR code (kept
  out of screenshots); the phone's camera opens the pairing page, which
  offers the APK and hands the settings to the app. No keys to type
  ([#14](https://github.com/GiamSoo23/Mox/issues/14), [#15](https://github.com/GiamSoo23/Mox/issues/15), [#16](https://github.com/GiamSoo23/Mox/issues/16), [#17](https://github.com/GiamSoo23/Mox/issues/17)).
- The pairing page, live on GitHub Pages at
  <https://giamsoo23.github.io/Mox/pair/> ([#16](https://github.com/GiamSoo23/Mox/issues/16)).
- A release workflow that builds a signed APK and the Mac app on a version
  tag ([#24](https://github.com/GiamSoo23/Mox/issues/24)).
- A testable `MoxCore` module for the Mac app, with XCTest suites run in CI
  ([#10](https://github.com/GiamSoo23/Mox/issues/10)). Mac, Android, the pairing page and the database all test
  against the same shared fixtures.
- A "Privacy and your data" section: Mox has no servers, and each user owns
  their data ([#66](https://github.com/GiamSoo23/Mox/issues/66)).
- Android saves received photos and videos to the Camera folder, so they
  show up in the gallery ([#43](https://github.com/GiamSoo23/Mox/issues/43)).
- First Android unit tests (16), run by CI on every PR ([#12](https://github.com/GiamSoo23/Mox/issues/12)).
- A secret scan (gitleaks) over the full history on every PR ([#59](https://github.com/GiamSoo23/Mox/issues/59)).
- This changelog and a bug log ([#52](https://github.com/GiamSoo23/Mox/issues/52)).

### Changed
- **Both apps speak schema v2**: they sign in as the Mox user, use the
  owner-only `mox` schema, store the file as `current`, identify each
  device, and refuse files over 50 MB before uploading
  ([#11](https://github.com/GiamSoo23/Mox/issues/11), [#12](https://github.com/GiamSoo23/Mox/issues/12), [#35](https://github.com/GiamSoo23/Mox/issues/35)).
- Settings live in the macOS Keychain and, on Android, are encrypted with
  an Android Keystore key. Android has no build-time credentials anymore;
  every APK is the same and is configured by pairing.
- A file sent while the receiving device was off or closed now arrives the
  next time it checks (the last handled file is remembered across
  launches).

### Fixed
- The first file sent after pairing (or after a first launch) on an empty
  slot wasn't downloaded ([#71](https://github.com/GiamSoo23/Mox/issues/71)).
- Android read a null `mime_type` as the string `"null"` ([#56](https://github.com/GiamSoo23/Mox/issues/56)).

### Security
- The anonymous v1 schema was removed: the publishable key alone can't read
  or write any Mox data, only the Mox user can ([#49](https://github.com/GiamSoo23/Mox/issues/49), [#40](https://github.com/GiamSoo23/Mox/issues/40)).
- The publishable key that had been committed was rotated and deleted, and
  the legacy `anon` / `service_role` keys were disabled. The old key now
  gets `401 Unregistered API key` ([#36](https://github.com/GiamSoo23/Mox/issues/36)).

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
  no longer misses a second file with the same extension. Verified on a
  real phone after applying the migrations
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

[Unreleased]: https://github.com/GiamSoo23/Mox/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/GiamSoo23/Mox/compare/v0.3.0...v0.5.0
[0.3.0]: https://github.com/GiamSoo23/Mox/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/GiamSoo23/Mox/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/GiamSoo23/Mox/releases/tag/v0.1.0
