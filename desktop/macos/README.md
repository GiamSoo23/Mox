# Mox · Mac

A SwiftPM menu-bar app. Lives in the status bar, doesn't show in the Dock.

## Build & run

```bash
cd desktop/macos
cp .env.example .env       # then edit .env and paste your Supabase creds
swift run -c release       # quick test from terminal
```

Once happy, build a proper `.app` bundle:

```bash
./build-app.sh
open Mox.app
```

Move `Mox.app` to `/Applications` if you want it to stick around. On first
launch Mox adds itself as a Login Item; switch that off any time with
**Launch at Login** in the menu.

## First-run permissions

macOS will prompt for two permissions; both are required:

1. **Automation → Finder** — so the hotkey can read the current Finder
   selection.
2. **Accessibility / Input Monitoring** — so the global hotkey works
   across all apps.

If you ever miss the prompt, enable them manually in
**System Settings → Privacy & Security**.

## Usage

- Select a file in Finder, hit `⌘⇧M`. The file is uploaded; you get a
  notification. (`⌘⇧U` was the original default, but Finder's
  *Go → Utilities* steals it while Finder is frontmost.)
- Click the Mox menu-bar icon to see the current file, copy a download
  link, or save it to `~/Downloads`.
- When the phone uploads, the file is saved to `~/Downloads` (with a
  unique name), put on the clipboard (images also as image data, so `⌘V`
  works in chat apps), the icon switches to a filled badge, and a
  notification fires.

Single-file rule: every upload replaces what was there. Zip a folder if
you need to send several files at once.

## Configuration

Mox reaches **your own** Supabase project as the Mox user (see
[backend/README.md](../../backend/README.md#making-yourself-the-owner)). It
keeps those settings in the **login Keychain**, readable only while the Mac
is unlocked and never synced.

For development you can put them in a `.env` (copy
[.env.example](.env.example)). It's read at launch from `$MOX_ENV`,
`~/.config/mox/.env`, the current directory, or the app bundle, and a
complete `.env` is copied into the Keychain:

| key                        | purpose                                        |
| -------------------------- | ---------------------------------------------- |
| `SUPABASE_URL`             | project URL                                    |
| `SUPABASE_PUBLISHABLE_KEY` | publishable key (`SUPABASE_ANON_KEY` also works) |
| `MOX_USER_EMAIL`           | the Mox user's email                           |
| `MOX_USER_PASSWORD`        | the Mox user's password                        |
| `MOX_HOTKEY`               | (optional) hotkey, default `cmd+shift+m`       |
| `MOX_POLL_SECONDS`         | (optional) poll interval, default `5`          |

## Pairing a phone

Menu bar icon → **Pair a Phone…** shows a QR code. Scan it with the phone's
camera: the [pairing page](https://giamsoo23.github.io/Mox/pair/) installs
Mox if needed and hands it the settings. The code contains the Mox user's
password, so the window stays out of screenshots and screen sharing.

## Tests

`MoxCore` (configuration, the protocol client, models, the pairing link)
has XCTest suites in `Tests/MoxCoreTests`, several of them driven by the
shared fixtures in `shared/fixtures/`. XCTest needs Xcode, so CI runs them
(`swift test`) on every PR. With only the Command Line Tools installed,
`swift build` still works.

## Lint

The app follows [SwiftLint](https://github.com/realm/SwiftLint)'s default
rules, configured in [.swiftlint.yml](.swiftlint.yml). CI runs it in strict
mode, so warnings fail the build.

```bash
brew install swiftlint
cd desktop/macos
swiftlint lint --strict
```

With only the Xcode Command Line Tools installed (no full Xcode), SwiftLint
can't find SourceKit. Point it at the tools first:

```bash
export TOOLCHAIN_DIR=/Library/Developer/CommandLineTools
```
