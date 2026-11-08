package com.mox.app

/**
 * App-wide constants. There are no credentials here: the app gets its
 * Supabase settings at runtime from the pairing QR (shared/PROTOCOL.md §8)
 * and keeps them encrypted in [SettingsStore].
 */
object Config {
    /** How often to poll the current file row, in milliseconds. */
    const val POLL_MS = 5_000L
}
