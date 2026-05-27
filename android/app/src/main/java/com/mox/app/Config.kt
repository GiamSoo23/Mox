package com.mox.app

/**
 * Mox configuration. Edit these two constants with your Supabase project's
 * URL and publishable / anon key before building.
 *
 * Either the legacy anon JWT (starts with `eyJ…`) or the new publishable
 * key (`sb_publishable_…`) works — both are safe to ship to clients.
 *
 * NEVER paste the `sb_secret_…` (service-role) key here. That key is for
 * trusted server code only.
 */
object Config {
    const val SUPABASE_URL = "https://fapiuwnlrlyrpuivxxte.supabase.co"
    const val SUPABASE_KEY = "sb_publishable_NvbYTNRpcGjiVnnRmc9z2g_yB9RDnVb"

    /** How often to poll the current_file row, in milliseconds. */
    const val POLL_MS = 5_000L

    /** Hard upload limit (also enforced by the storage bucket). */
    const val MAX_BYTES = 500L * 1024L * 1024L
}
