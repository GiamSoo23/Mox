# Mox

<!-- DEMO VIDEO: drag the video file here in GitHub's web editor (10 MB at most). -->
https://github.com/user-attachments/assets/03f4bb3e-eb76-4dc7-8794-5c927f6aafd4


**Send a file between your Mac and your Android phone in one step. It lands on the clipboard, ready to paste.**

[![macOS CI](https://github.com/GiamSoo23/Mox/actions/workflows/macos.yml/badge.svg)](https://github.com/GiamSoo23/Mox/actions/workflows/macos.yml)
[![Android CI](https://github.com/GiamSoo23/Mox/actions/workflows/android.yml/badge.svg)](https://github.com/GiamSoo23/Mox/actions/workflows/android.yml)
[![Latest release](https://img.shields.io/github/v/release/GiamSoo23/Mox)](https://github.com/GiamSoo23/Mox/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

<!-- DEMO VIDEO: drag the video file here in GitHub's web editor (10 MB at most). -->

AirDrop only works between Apple devices. Mox works between a **Mac or
Windows PC** and an **Android phone or iPhone**:

- **Computer → phone:** select a file and press **⌘⇧M** (Mac) or **Ctrl+Shift+M** (Windows). It arrives in seconds.
- **Phone → computer:** tap **Share → Mox**. The file lands in Downloads.
- **Text too:** copy something on one device and paste it on the other.

Mox runs on **your own** free Supabase project. It has no servers and no
accounts of its own, so nobody else holds your files.

## Install

1. **Download** Mox for Mac or Windows from the [latest release](https://github.com/GiamSoo23/Mox/releases/latest) and open it.
2. **Sign in with Supabase** and choose where Mox keeps your files. Mox sets everything up.
3. **Scan the QR code** with your Android phone or iPhone to set up Mox there and pair it.

| Welcome | Choose a project | Automatic setup |
|---|---|---|
| <img src="docs/assets/install/welcome.png" width="270" alt="Welcome to Mox"> | <img src="docs/assets/install/choose-project.png" width="270" alt="Choosing a project"> | <img src="docs/assets/install/progress.png" width="270" alt="Setup progress"> |

You need macOS 13+ or Windows, Android 8+ or an iPhone, and a free Supabase account. New to Supabase, or
macOS blocked the app? The **[install guide](docs/INSTALL.md)** walks through
every screen.

## How it works

```mermaid
flowchart LR
    MAC["Mox for Mac (Swift)<br/>or Windows (C#)"]
    AND["Mox for Android (Kotlin)<br/>or iPhone (web app)"]
    subgraph SUPA["Your own Supabase project"]
        direction TB
        ST[("Storage<br/>the file")]
        PG[("Postgres<br/>who sent what")]
    end
    MAC <--> SUPA
    AND <--> SUPA
```

Sending uploads the file, then updates one database row. The other device
hears that the row changed, downloads the file and copies it to the clipboard:

```mermaid
sequenceDiagram
    actor You
    participant Mac as Mox (Mac)
    participant DB as Your Supabase
    participant Phone as Mox (Android)
    You->>Mac: Press ⌘⇧M on a file
    Mac->>DB: Upload the file, update the row
    DB-->>Phone: The row changed
    Phone->>DB: Download the file
    Phone-->>You: Saved and on the clipboard
```

## Good to know

- One file at a time, up to 50 MB. Files only, not plain text.
- Free Supabase projects pause after a week without use. You can restore them from the dashboard.
- macOS asks you to approve the app once, because it isn't notarized by Apple.
- On iPhone, Mox is a home screen web app plus a shortcut, so receiving takes one tap on the notification.
- The apps aren't signed by Apple or Microsoft yet, so macOS and Windows warn once.

## Learn more

| | |
|---|---|
| **[Install guide](docs/INSTALL.md)** | Every step with pictures, troubleshooting, uninstalling |
| **[Architecture](docs/ARCHITECTURE.md)** | Engineering highlights, tests, data model, each client |
| **[Security and privacy](SECURITY.md)** | Where your data lives and how it's protected |
| **[Design decisions](docs/DESIGN.md)** | Why it works this way, and what was rejected |
| **[Protocol](shared/PROTOCOL.md)** | The contract every client follows |
| **[Bug log](docs/BUGS.md)** · **[Changelog](CHANGELOG.md)** | What broke and why, and what changed in each version |
| **[Contributing](CONTRIBUTING.md)** | Building from source and running the tests |

Built with Swift, C#, Kotlin, TypeScript and Supabase. [MIT license](LICENSE).
