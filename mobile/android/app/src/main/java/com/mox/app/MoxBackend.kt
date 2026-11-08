package com.mox.app

import android.content.ContentResolver
import android.net.Uri
import java.io.File
import java.io.OutputStream

/**
 * Everything the app needs from the backend. [SupabaseRepo] talks to
 * Supabase over REST. Tests can supply a fake, so the ViewModel's logic can
 * be checked without a network.
 */
interface MoxBackend {
    /** The current file, or null if nothing has been sent yet. */
    suspend fun fetchCurrent(): CurrentFile?

    /** Uploads a file from a content URI and makes it the current file. */
    suspend fun uploadFromContentUri(
        resolver: ContentResolver,
        uri: Uri,
        displayName: String,
        sizeBytes: Long,
        mime: String?
    ): CurrentFile

    /** A short-lived URL to download [path] without credentials. */
    suspend fun signedDownloadUrl(path: String, expiresIn: Int = 600): String

    /** Downloads the current file into [file]. */
    suspend fun downloadTo(file: File, current: CurrentFile)

    /** Downloads the current file into [out], streaming. */
    suspend fun downloadToStream(out: OutputStream, current: CurrentFile)
}
