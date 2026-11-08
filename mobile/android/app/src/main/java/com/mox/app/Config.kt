package com.mox.app

/**
 * Mox configuration.
 *
 * The Supabase project URL and publishable key are read at build time from
 * `mobile/android/local.properties`, which git ignores, so they never live
 * in source control:
 *
 *     mox.supabaseUrl=https://<project-ref>.supabase.co
 *     mox.supabaseKey=sb_publishable_...
 *
 * This is temporary: v2 configures the app at runtime by scanning the pairing
 * QR (#12, #17). Never use the secret (`sb_secret_...`) key in a client.
 */
object Config {
    val supabaseUrl: String = BuildConfig.SUPABASE_URL
    val supabaseKey: String = BuildConfig.SUPABASE_KEY

    /** False when local.properties had no credentials at build time (CI builds). */
    val isConfigured: Boolean = supabaseUrl.isNotBlank() && supabaseKey.isNotBlank()

    const val NOT_CONFIGURED_MESSAGE =
        "Mox isn't configured. Add mox.supabaseUrl and mox.supabaseKey to " +
            "local.properties and rebuild."

    /** How often to poll the current_file row, in milliseconds. */
    const val POLL_MS = 5_000L

    /** Hard upload limit (also enforced by the storage bucket). */
    const val MAX_BYTES = 500L * 1024L * 1024L
}
