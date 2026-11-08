# Mox · Android

Plain Compose + OkHttp app. No external SDK — small APK.

## Configure: pair with your computer

There's nothing to configure at build time: every APK is the same, and no
credentials are compiled in. The app gets its settings by **pairing**:

1. On your computer, open Mox → **Pair a Phone…**.
2. Scan the QR code with the phone's camera. The
   [pairing page](https://giamsoo23.github.io/Mox/pair/) offers the APK if
   Mox isn't installed, then **Open in Mox** hands the settings to the app
   (`mox://pair`, PROTOCOL.md §8).
3. Mox signs in as your Mox user, checks the schema, and only then stores
   the settings, encrypted with a key kept in the Android Keystore.

The pairing card in the app also accepts the link pasted by hand (from the
Mac's **Copy Link** button). The `mox.supabaseUrl` / `mox.supabaseKey`
entries an older build read from `local.properties` are no longer used.

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
