# Mox backend

Mox has no server of its own. The backend is a Supabase project: Postgres
holds one row describing the current file, and Storage holds the file. This
folder is a [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started)
project, so the schema lives in versioned migrations:

```
backend/supabase/
├── config.toml          local stack settings (CLI defaults, project_id = "mox")
└── migrations/          SQL applied in timestamp order
    └── 20260526000000_initial_schema.sql
```

## Set up a Supabase project

Create a free project at [supabase.com](https://supabase.com), then pick one
of these:

**Option A: dashboard.** Open **SQL Editor → New query**, paste each file in
`supabase/migrations/` in order, and click **Run**. The SQL is idempotent,
so running it again is safe.

**Option B: CLI.** No install needed, `npx` downloads it:

```bash
cd backend
npx supabase login
npx supabase link --project-ref <your-project-ref>   # from the project URL
npx supabase db push                                 # applies pending migrations
```

Then, from **Project Settings → API Keys**, copy the project URL and the
**publishable** key into:

- `desktop/macos/.env` (copy `desktop/macos/.env.example` first)
- `mobile/android/app/src/main/java/com/mox/app/Config.kt`

Never put the secret (`sb_secret_…`) key in a client.

## Run it locally

Needs Docker (Docker Desktop or OrbStack).

```bash
cd backend
npx supabase start       # Postgres, PostgREST, Storage… in containers
npx supabase db reset    # recreate the database from the migrations
npx supabase stop
```

## Schema overview (v1)

- **Storage bucket `mox`:** private. The bucket allows 500 MB, but the
  Supabase free plan rejects uploads over 50 MB
  ([#35](https://github.com/GiamSoo23/Mox/issues/35)). Each upload is stored
  as `current.<ext>`.
- **Table `public.current_file`:** exactly one row (`id = 1`) describing
  whatever is currently in the bucket. Both clients poll it every few
  seconds to notice a new file from the other device.

Schema v2 is planned in [docs/DESIGN.md §8](../docs/DESIGN.md) and tracked
in [#7](https://github.com/GiamSoo23/Mox/issues/7).

## Rotating credentials

If a key leaks: **Project Settings → API Keys**, create a new publishable
key, update both clients, then delete the old key.
