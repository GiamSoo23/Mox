# Mox backend

Mox has no server of its own. The backend is a Supabase project: Postgres
holds one row describing the current file, and Storage holds the file. This
folder is a [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started)
project, so the schema lives in versioned migrations:

```
backend/supabase/
├── config.toml          local stack settings (CLI defaults, project_id = "mox")
├── migrations/          SQL applied in timestamp order
└── tests/database/      pgTAP tests
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
- the Android app gets them by scanning the Mac's pairing QR code

Never put the secret (`sb_secret_…`) key in a client.

## Run it locally

Needs Docker (Docker Desktop or OrbStack).

```bash
cd backend
npx supabase start       # Postgres, PostgREST, Storage… in containers
npx supabase db reset    # recreate the database from the migrations
npx supabase stop
```

## Schema

### v2: the `mox` schema

Migrations `20261107*` add schema v2 and `20261108120000_drop_v1.sql` removes v1 (design: [docs/DESIGN.md §8](../docs/DESIGN.md)):

- **`mox.meta`:** one row with `schema_version` (2) and `owner_id`, the only
  auth user allowed to use Mox.
- **`mox.current_file`:** the one slot: name, MIME type, size (up to 50 MB),
  `kind` (`file` / `bundle`), `item_count`, `source_platform`,
  `source_device_id` and `uploaded_at` (refreshed on every replace).
- **Storage:** bucket `mox`, capped at 50 MB, holds the file as `current`.
- **Access:** row level security on everything, and only the owner gets in.
  The anon role has no access to v2, so a public publishable key (common
  when the project also runs a website) can't read your files.

### Making yourself the owner

The setup wizard (#22) will do this for you. Until then, by hand:

1. **Authentication → Users → Add user → Create new user**. Use any email
   and a long random password, and tick **Auto Confirm User**.
2. In the SQL editor, with that user's UUID:
   ```sql
   update mox.meta set owner_id = '<user-uuid>' where id = 1;
   ```
3. **Project Settings → API → Exposed schemas**: add `mox`.

### v1 (removed)

v1's `public.current_file`, its anonymous policies and the `current.<ext>`
storage rules were dropped once both apps spoke v2
([#49](https://github.com/GiamSoo23/Mox/issues/49)). Leftover `current.<ext>`
files can only be deleted through the Storage API, so remove them once from
the dashboard (**Storage → mox**) to free the space.

## Tests

pgTAP suites in `supabase/tests/database/` cover the constraints and,
above all, who can read and write what. CI runs them against a throwaway
stack on every PR that touches `backend/`. Locally (needs Docker):

```bash
npx supabase start && npx supabase test db
```

## Rotating credentials

If a key leaks: **Project Settings → API Keys**, create a new publishable
key, update both clients, then delete the old key.
