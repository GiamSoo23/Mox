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
| `text-with-many-items.json` | a text has exactly 1 item |
| `unknown-kind.json` | `kind` is `file`, `bundle` or `text` |
| `missing-device-id.json` | `source_device_id` is required |
| `empty-name.json`, `name-too-long.json` | `original_name` is 1–255 characters |
| `second-row.json` | `id` is always 1 |

`valid/max-size-with-unknown-field.json` carries an extra field on purpose:
clients must **ignore fields they don't know**, so the schema can grow
without breaking older apps.

## `pairing/`

Pairing links (PROTOCOL.md §8), one per `.txt` file. All values are fake.

| Folder | Clients must… |
|---|---|
| `valid/` | parse the `.txt` into exactly the fields in the matching `.json` |
| `invalid/` | refuse it and store nothing |

The valid set covers the plain link, the `mox://pair?` hand-off form, a
`+` in the email (decoders must not turn it into a space), a non-ASCII
desktop name, a missing name (`desktopName: null`), and a trailing slash
plus an unknown key (both tolerated).

| Invalid fixture | Breaks the rule |
|---|---|
| `secret-key.txt` | a `sb_secret_` key must never be accepted |
| `legacy-anon-key.txt` | only `sb_publishable_` keys |
| `http-project-url.txt`, `project-url-with-path.txt` | `https://` and a bare host |
| `missing-password.txt`, `empty-email.txt` | required keys present and non-empty |
| `short-password.txt` | password is 16–128 characters |
| `email-without-at.txt` | exactly one `@` |
| `name-too-long.txt` | name is at most 64 characters |
| `future-version.txt` | only `v=1`; newer versions mean "update the app" |
| `duplicate-key.txt` | no key twice |
| `no-parameters.txt` | a link without parameters |

Bundles (#18) get their own folder when that spec is written.
