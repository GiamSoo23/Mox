# Mox

One file at a time, between your Mac and your phone.

Mox is a tiny relay app for sending a single file (up to 500 MB) between your
Mac and an Android device using a private Supabase bucket as the in-between.

- **Mac**: menu-bar app. Select a file in Finder, press a global hotkey
  (default `⌘⇧U`), and it's uploaded.
- **Android**: share target. From Gallery / WhatsApp / anywhere, share to
  *Mox*. The file is uploaded. The latest file is always available to pull
  on either side.

Only **one** file lives in Mox at a time — the newest upload from either
device replaces the previous one. To send multiple files, zip them.

## Layout

```
mox/
├── supabase/   SQL schema + storage bucket setup
├── mac/        Swift menu-bar app (SwiftPM)
└── android/    Kotlin Android app (Gradle)
```

## Setup (one time, ~5 min)

1. Create a free Supabase project at https://supabase.com.
2. In the project's SQL editor, paste the contents of
   [supabase/schema.sql](supabase/schema.sql) and run it.
3. From **Project Settings → API**, copy the **Project URL** and **anon
   public key**.
4. Paste them into:
   - [mac/.env](mac/.env.example) — copy `.env.example` to `.env`
   - [android/app/src/main/java/com/mox/app/Config.kt](android/app/src/main/java/com/mox/app/Config.kt)
5. Build each side — see [mac/README.md](mac/README.md) and
   [android/README.md](android/README.md).

## Security notes

Mox uses Supabase's **anon key** baked into both clients. That key plus
your project URL is enough for anyone holding it to read/write your single
file. Keep the binaries to yourself. If you ever share a build or suspect a
leak, rotate the anon key in the Supabase dashboard and rebuild.

The bucket is **private**; clients access it via signed URLs.
