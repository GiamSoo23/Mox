# Security

Mox has no servers. Each person's data lives in their own Supabase project,
and Mox's author can't see it.

## Reporting a vulnerability

Please **don't open a public issue**. Use GitHub's
[private vulnerability report](https://github.com/GiamSoo23/Mox/security/advisories/new)
and include how to reproduce the problem. Mox is maintained by one person, so
a reply may take a few days.

Only the [latest release](https://github.com/GiamSoo23/Mox/releases/latest) gets fixes.

## Privacy and your data

Mox's author runs no backend and can't see anything you send.

- **Files and settings** stay in your own Supabase project and on your devices.
- **The current file stays in your project** until the next one replaces it. Mox keeps one file at a time.
- **Your Mox password** is kept in the macOS Keychain and in an Android Keystore-encrypted store.
- **The pairing page** reads its data in your browser. The page has no analytics and no third-party scripts.
- **No analytics or telemetry** in any app.

Supabase hosts your project under [its own terms](https://supabase.com/privacy).
If other people administer your Supabase organization, they could read your
files. The setup window warns you when that's the case.

## Security model

| Asset | Where it lives | How it's protected |
|---|---|---|
| Your files | A private Storage bucket in your project | Owner-only row level security. Downloads use signed URLs that expire |
| Mox user's password | macOS Keychain, Android Keystore-encrypted store | Generated at random, 32 characters, one per project |
| Publishable key | On your devices | Grants nothing by itself: the `anon` role has no access to Mox |
| Project secret key | Nowhere | Read once during setup to create the Mox user, then dropped |
| Supabase sign-in token | Memory, during setup only | Never written to disk |

**The pairing QR is a secret.** It contains the Mox user's password. The Mac
shows it only on request and excludes that window from screenshots and screen
sharing. Don't send a photo of it.

**Shared projects.** Mox is isolated from other apps in the same project.
It isn't isolated from people who administer that Supabase organization: they
could read your files. The setup window warns you. End-to-end encryption is
being studied ([#78](https://github.com/GiamSoo23/Mox/issues/78)).

**The OAuth client secret.** Official Mac builds include the secret of Mox's
Supabase OAuth app, and anyone can extract it from the binary. It doesn't give
access to anyone's account: signing in still needs PKCE, the person's approval
in the browser, and a redirect to their own computer.

**Downloads.** The APK is signed with Mox's release key, and CI refuses to
publish one signed with anything else. The Mac app is ad-hoc signed and isn't
notarized. Each release includes `SHA256SUMS.txt`.

## What's tested

- [pgTAP tests](backend/supabase/tests/database/mox_v2_test.sql) check who can read and write what, on every backend pull request.
- gitleaks scans the full git history on every pull request, and CI looks for the OAuth secret's exact value.
