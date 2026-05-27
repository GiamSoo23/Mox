# Mox · Mac

A SwiftPM menu-bar app. Lives in the status bar, doesn't show in the Dock.

## Build & run

```bash
cd mac
cp .env.example .env       # then edit .env and paste your Supabase creds
swift run -c release       # quick test from terminal
```

Once happy, build a proper `.app` bundle:

```bash
./build-app.sh
open Mox.app
```

Move `Mox.app` to `/Applications` if you want it sticky, and add it to
**System Settings → General → Login Items** so it starts with you.

## First-run permissions

macOS will prompt for two permissions; both are required:

1. **Automation → Finder** — so the hotkey can read the current Finder
   selection.
2. **Accessibility / Input Monitoring** — so the global hotkey works
   across all apps.

If you ever miss the prompt, enable them manually in
**System Settings → Privacy & Security**.

## Usage

- Select a file in Finder, hit `⌘⇧U`. The file is uploaded; you get a
  notification.
- Click the Mox menu-bar icon to see the current file, copy a download
  link, or save it to `~/Downloads`.
- When the phone uploads, the icon turns blue and a notification fires.

Single-file rule: every upload replaces what was there. Zip a folder if
you need to send several files at once.

## Configuration

`.env` keys (loaded from `./.env`, `~/.config/mox/.env`, or
`$MOX_ENV`):

| key                 | purpose                                      |
| ------------------- | -------------------------------------------- |
| `SUPABASE_URL`      | project URL                                  |
| `SUPABASE_ANON_KEY` | anon JWT                                     |
| `MOX_HOTKEY`        | (optional) hotkey, e.g. `cmd+shift+u`        |
| `MOX_POLL_SECONDS`  | (optional) poll interval, default `5`        |
