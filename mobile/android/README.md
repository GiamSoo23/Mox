# Mox · Android

Plain Compose + OkHttp app. No external SDK — small APK.

## Configure

Edit [app/src/main/java/com/mox/app/Config.kt](app/src/main/java/com/mox/app/Config.kt)
with your Supabase project URL and **publishable** (or legacy anon) key.

Never paste your `sb_secret_…` key here — that one is server-only.

## Build

You need the Android SDK installed (via Android Studio, or `sdkmanager`
from the command line). Then either:

```bash
# From the mobile/android/ directory:
./gradlew assembleRelease     # produces app/build/outputs/apk/release/app-release.apk
./gradlew installDebug        # builds + installs on a connected device
```

…or open `mobile/android/` in Android Studio and hit Run.

The release APK is **debug-signed** by default — fine for sideloading to
your own phone. For Play distribution you'd need a real keystore (out of
scope for a personal tool).

## Install on your Samsung

Easiest path:

1. `./gradlew assembleDebug` (or release).
2. Transfer the APK to the phone (USB, Google Drive, email — anything).
3. On the phone, tap the APK and allow installs from this source if
    prompted.

Once installed, the *Mox* target appears in the standard Android **Share**
sheet from Gallery, WhatsApp, Files, Chrome, etc. Tap any file → Share →
Mox → it uploads and replaces whatever was there before.

## First-run permission

On Android 13+, the OS will ask once for notification permission. Granting
it is optional — Mox works either way.

## Lint

Kotlin style is checked with [ktlint](https://pinterest.github.io/ktlint/)
(Android Studio code style), run through Gradle with no extra plugin. Rules
live in the repo's [.editorconfig](../../.editorconfig).

```bash
./gradlew ktlintCheck    # report problems (also part of ./gradlew check)
./gradlew ktlintFormat   # fix everything that can be fixed automatically
```

Gradle 9 needs JDK 17–21 to run. If your default Java is newer, point
`JAVA_HOME` at a JDK 21 (Android Studio's bundled JBR works).
