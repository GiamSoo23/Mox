# Contributing to Mox

Thanks for helping. Mox has one design rule above the others: **each person
owns their data, and Mox has no servers.** Changes that need a central backend
won't be accepted. [docs/DESIGN.md](docs/DESIGN.md) explains why things are the
way they are.

## Build from source

- **Mac:** `cd desktop/macos && ./build-app.sh && open Mox.app`. The setup window asks for a Supabase personal access token, because "Sign in with Supabase" needs the OAuth client secret only official builds carry. See [desktop/macos/README.md](desktop/macos/README.md).
- **Android:** `cd mobile/android && ./gradlew installDebug`, then pair with the Mac's QR code. See [mobile/android/README.md](mobile/android/README.md).
- **Backend by hand** (optional): see [backend/README.md](backend/README.md).

## How work happens

1. **Open an issue first**, for bugs and ideas alike, so we can agree before you write code.
2. Create a branch from `main`, named by area: `android/…`, `macos/…`, `backend/…`, `fix/…`, `docs/…`.
3. Write [Conventional Commits](https://www.conventionalcommits.org/), such as `fix(android): …`, in small steps.
4. Open a pull request with `Closes #N`. It's merged with **Rebase and merge** once CI is green.

If your change needs a real device to verify, say what you tested in the pull request.

## Running the checks

| Area | From | Command |
|---|---|---|
| macOS | `desktop/macos` | `swift test` and `swiftlint lint --strict` (both need Xcode) |
| Android | `mobile/android` | `./gradlew ktlintCheck testDebugUnitTest` |
| Database | `backend` | `npx supabase start`, then `npx supabase test db` (needs Docker) |
| Pairing page | `web` | `node --test pair/pairing.test.js` |

## Changing how devices talk to each other

[shared/PROTOCOL.md](shared/PROTOCOL.md) is the API, because there's no server
to version. If you change it, update the [shared fixtures](shared/fixtures/) and
every client in the same pull request.

## Changing the database

Add a new migration under `backend/supabase/migrations/`. Don't edit one that
has shipped. Migrations must be safe to run again and must keep row level
security owner-only. Add a pgTAP check, then regenerate the copy inside the Mac app:

```bash
python3 desktop/macos/scripts/sync-migrations.py
```

## Secrets

Never commit keys, passwords or a filled-in `.env`. Test values live in the
paths allowed by [.gitleaks.toml](.gitleaks.toml), and CI scans the full history.

## Code of conduct

Taking part means following the [Code of Conduct](CODE_OF_CONDUCT.md).
