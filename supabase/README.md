# Supabase setup

1. Create a project at https://supabase.com (free tier is plenty).
2. Open **SQL Editor → New query**, paste [schema.sql](schema.sql), and
   click **Run**.
3. Open **Project Settings → API** and copy:
   - **Project URL** (looks like `https://xxxx.supabase.co`)
   - **anon public key** (a long JWT)
4. Paste those into:
   - `mac/.env` (copy `mac/.env.example` first)
   - `android/app/src/main/java/com/mox/app/Config.kt`

## Schema overview

- **Storage bucket `mox`** — private, 500 MB file size cap. Holds at most
  one object at a time named `current.<ext>`.
- **Table `public.current_file`** — exactly one row (`id = 1`) describing
  whatever is currently in the bucket. Updated atomically when a new file
  is sent.

Both clients poll this table every few seconds to know when a fresh file
has arrived from the other device.

## Rotating credentials

If you ever leak the anon key:

1. Supabase dashboard → **Project Settings → API → Reset anon key**.
2. Update both client configs and rebuild.
