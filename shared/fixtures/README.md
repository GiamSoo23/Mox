# Shared fixtures

JSON files every Mox client loads in its own test suite (Swift, Kotlin, C#),
so all of them interpret rows the same way. CI also inserts each row into
the real schema with [check-rows.sh](check-rows.sh), so the fixtures can't
drift away from the database constraints.

## `rows/`

A row of `mox.current_file` exactly as PostgREST returns it (one object).

| Folder | Clients must… | Database must… |
|---|---|---|
| `valid/` | parse it and treat it as a usable file | accept it |
| `invalid/` | reject it: no download, a clear error | reject it |

| Invalid fixture | Breaks the rule |
|---|---|
| `v1-platform-name.json` | `source_platform` is `macos`, not v1's `mac` |
| `unknown-platform.json` | only `macos`, `windows`, `android`, `ios` |
| `too-large.json` | `size_bytes` ≤ 52 428 800 (50 MB) |
| `empty-file.json` | `size_bytes` ≥ 1 |
| `bundle-with-one-item.json` | a bundle has 2+ items |
| `file-with-many-items.json` | a file has exactly 1 item |
| `unknown-kind.json` | `kind` is `file` or `bundle` |
| `missing-device-id.json` | `source_device_id` is required |
| `empty-name.json`, `name-too-long.json` | `original_name` is 1–255 characters |
| `second-row.json` | `id` is always 1 |

`valid/max-size-with-unknown-field.json` carries an extra field on purpose:
clients must **ignore fields they don't know**, so the schema can grow
without breaking older apps.

Pairing payloads (#14) and bundles (#18) get their own folders when those
specs are written.
