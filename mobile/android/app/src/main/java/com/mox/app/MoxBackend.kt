package com.mox.app

import android.content.ContentResolver
import android.net.Uri
import java.io.File
import java.io.OutputStream

/**
 * Everything the app needs from the backend (shared/PROTOCOL.md §4).
 * [SupabaseRepo] talks to Supabase over REST; tests can supply a fake.
 */
interface MoxBackend {
    /** Signs in and checks for schema v2 and an owner (§4.1). */
    suspend fun checkSchema()

    /** The current file, or null if nothing has been sent yet (§4.2). */
    suspend fun fetchCurrent(): CurrentFile?

    /** Uploads a file from a content URI and makes it the current file (§4.3, §4.4). */
    suspend fun uploadFromContentUri(
        resolver: ContentResolver,
        uri: Uri,
        displayName: String,
        sizeBytes: Long,
        mime: String?
    ): CurrentFile

    /** Uploads plain text and makes it the current item (#101). */
    suspend fun uploadText(text: String): CurrentFile

    /** A short-lived URL to download the current file without credentials (§4.5). */
    suspend fun signedDownloadUrl(expiresIn: Int = 600): String

    /** Downloads the current file into [file]. */
    suspend fun downloadTo(file: File)

    /** Downloads the current file into [out], streaming (§4.6). */
    suspend fun downloadToStream(out: OutputStream)
}

/** An error a person can act on, with a message written for them. */
class MoxException(message: String) : Exception(message)
