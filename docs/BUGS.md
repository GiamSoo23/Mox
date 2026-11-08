# Bug log

Every bug found in Mox, with the notable ones explained. **GitHub issues
labeled [`bug`](https://github.com/GiamSoo23/Mox/issues?q=label%3Abug) are
the source of truth.** This page is the readable summary: what happened,
why, and what keeps it from coming back.

Last updated: 2026-11-07.

## Index

| Issue | Bug | Area | How it was found | Status |
|---|---|---|---|---|
| [#48](https://github.com/GiamSoo23/Mox/issues/48) | `uploaded_at` isn't refreshed when the file is replaced, so Android can miss files | backend | Reviewing the upsert while writing schema v2, then **reproduced on a real phone** | **Fixed** (0.3.0), applied to the live project and verified on the phone |
| [#34](https://github.com/GiamSoo23/Mox/issues/34) | Old storage object left behind when the extension changes | backend | Code review for the README | Fixed by design in v2. Done once clients use v2 |
| [#35](https://github.com/GiamSoo23/Mox/issues/35) | Uploads over 50 MB fail; docs promised 500 MB | backend, docs | Checking the free plan's limits | Cap and checks in 0.3.0. Client checks pending |
| [#36](https://github.com/GiamSoo23/Mox/issues/36) | Supabase key committed in Android `Config.kt` | security | Review before making the repo public | Open, fixed by #12 + key rotation |
| [#2](https://github.com/GiamSoo23/Mox/issues/2) | macOS README said the hotkey was ⌘⇧U; it's ⌘⇧M | docs | Comparing the docs to the code | Fixed in 0.1.0 |
| — | ⌘⇧U didn't work while Finder was in front | macOS | Daily use, before versioning | Fixed before 0.1.0 |
| — | Android didn't copy received files to the clipboard | Android | Daily use, before versioning | Worked around in 0.1.0 |

Known limitations, which aren't bugs, are tracked as enhancements:
[#37](https://github.com/GiamSoo23/Mox/issues/37) (Android only receives
while the app is open).

## Write-ups

### #48: Android could silently ignore a second file

**Symptom.** Send two PNG screenshots in a row from the Mac: the phone could
pick up the first and never the second. No error anywhere.

**Root cause.** Both apps replace the row with a PostgREST upsert and don't
send `uploaded_at`. PostgREST turns that into
`INSERT … ON CONFLICT (id) DO UPDATE SET <only the columns sent>`, so
`uploaded_at` kept the time of the very first upload. Android recognizes a
new file by `storage_path|uploaded_at`. Two PNGs are both stored as
`current.png` with the same old timestamp, so the second one looked
already handled.

**Fix.** A `BEFORE UPDATE` trigger sets `uploaded_at = now()` on every
replace, on the v1 and v2 tables.

**Prevention.** A pgTAP test runs the exact SQL PostgREST generates and
checks that the timestamp changes. v2 also changes how clients dedupe: they
compare the sending device's id plus `uploaded_at`, not a file path
([PROTOCOL.md §6](../shared/PROTOCOL.md)).

**Confirmed in real use.** While testing #45 on a Galaxy S23, the phone's
stored key turned out to be `current.pdf|2026-05-27T03:32:41…`: `uploaded_at`
had been stuck at the very first upload for over five months. A `.jpeg`
arrived, and then a second `.jpeg` was silently ignored, exactly as
predicted. The bug was found by reading the code, then confirmed on the
device.

**Verified fixed.** After applying the migrations to the live project, two
different `.jpeg` files sent 13 seconds apart both landed in the Camera
folder, and the stored key now carries a fresh timestamp
(`current.jpeg|2026-11-08T03:48:08…`).

**Lesson.** "Upsert" doesn't mean "every column is rewritten". Server-side
defaults only apply on insert.

### #34: files piling up in the bucket

**Symptom.** None visible. The bucket slowly fills with old files.

**Root cause.** Each upload is stored as `current.<ext>`. Send a PDF, then a
JPG: `current.jpg` replaces nothing, and `current.pdf` stays forever.

**Fix.** v2 always stores the file as `current`. The extension comes from
`original_name` when saving. v1 leftovers are removed in #49.

**Prevention.** Storage policies only allow the name `current` for v2, so a
client can't recreate the problem.

### #35: the 500 MB promise

**Symptom.** Files between 50 MB and 500 MB fail with a server error, even
though the bucket and the README said 500 MB.

**Root cause.** The Supabase free plan caps every upload at 50 MB no matter
what the bucket says. Nobody had sent a file that big.

**Fix.** The bucket cap and a database check are both 50 MB now. Clients
will check the size before uploading and explain the problem (#11, #12).

**Prevention.** pgTAP tests pin the cap, and an invalid fixture
(`too-large.json`) makes every client test reject it.

### #36: a key in the source code

**What happened.** The Android app compiled the project URL and the
publishable key into `Config.kt`, so they're in the git history.

**Risk.** With v1's policies, anyone holding that key can read and replace
the current file. The repo is still private, so it hasn't leaked.

**Fix.** Configuration moves to runtime (#12). Then the old key is rotated,
which makes the copy in the history useless, and gitleaks scans the history
before the repo goes public. v2 also no longer trusts the key alone (#40).

### ⌘⇧U and Finder (before versioning)

**Symptom.** The send hotkey did nothing when Finder was the frontmost app,
which is exactly when you'd press it.

**Root cause.** Finder's *Go → Utilities* menu item uses ⌘⇧U and takes it
before a global hotkey sees it.

**Fix.** The default became ⌘⇧M, with a comment in `Config.swift`
explaining why. You can still pick another one with `MOX_HOTKEY`.

### The Android clipboard (before versioning)

**Symptom.** Files from the Mac were saved, but never landed on the
clipboard.

**Root cause.** Android 10+ restricts clipboard access for apps that aren't
in the foreground, and Samsung enforces it strictly.

**Workaround.** Mox tries anyway. If that doesn't work, tapping the
notification opens a transparent activity that's in the foreground for one
frame, long enough to set the clip. Making it fully automatic is #37.

## Development environment problems

Problems with the tools, not with Mox. They're written down so the next
person doesn't lose an hour.

| Problem | Cause | Fix |
|---|---|---|
| Gradle fails to start | Gradle 9 doesn't run on JDK 26 | Point `JAVA_HOME` at JDK 17–21 (Android Studio's JBR works) |
| `missing required module 'SwiftShims'` after moving folders | The SwiftPM `.build` cache stores absolute paths | `swift package clean` |
| SwiftLint crashes loading `sourcekitdInProc` | Only the Command Line Tools are installed, no Xcode | `export TOOLCHAIN_DIR=/Library/Developer/CommandLineTools` |
| `brew install supabase` refuses to install | Outdated Command Line Tools | Use `npx supabase …` (no install), or update the tools |
| `swift test` can't find XCTest | XCTest ships with Xcode, not the Command Line Tools | Install Xcode (free) |

## Adding an entry

1. Open an issue with the `bug` label first (what you saw, how to
   reproduce it).
2. When it's fixed, add a row to the index. Add a write-up if the cause was
   surprising or the fix teaches something.
3. Add a line under **Fixed** in [CHANGELOG.md](../CHANGELOG.md).
