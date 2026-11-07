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

`.env` keys (loaded from `$MOX_ENV`, `~/.config/mox/.env`, `./.env`, or
the app bundle's `Resources/`):

| key                 | purpose                                      |
| ------------------- | -------------------------------------------- |
| `SUPABASE_URL`      | project URL                                  |
| `SUPABASE_ANON_KEY` | anon JWT                                     |
| `MOX_HOTKEY`        | (optional) hotkey, default `cmd+shift+m`     |
| `MOX_POLL_SECONDS`  | (optional) poll interval, default `5`        |

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
