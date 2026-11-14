package com.mox.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.content.FileProvider
import java.io.File
import java.io.IOException
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** This installation's id (PROTOCOL.md §1), written into every row it sends. */
object DeviceIdentity {
    private const val KEY = "deviceId"

    fun id(context: Context): String {
        val prefs = context.getSharedPreferences(FileReceiver.PREFS, Context.MODE_PRIVATE)
        return prefs.getString(KEY, null)
            ?: UUID.randomUUID().toString().also { prefs.edit().putString(KEY, it).apply() }
    }
}

/**
 * Receives what other devices send (PROTOCOL.md §6). The screen and the
 * listening service both use it, so what was handled lives in preferences
 * and one lock keeps a file from being received twice.
 */
class FileReceiver(
    context: Context,
    private val backend: MoxBackend,
    private val deviceId: String
) {
    private val ctx = context.applicationContext
    private val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Reads the slot, receives its file if it's new, and returns it. */
    suspend fun check(): CurrentFile? = LOCK.withLock {
        val current = backend.fetchCurrent()
        val lastHandled = prefs.getString(KEY_LAST_HANDLED, null)
        if (lastHandled == null) {
            // First read after install or pairing: remember what's in the slot,
            // even when it's empty, so the next file from another device counts
            // as new (#71). What's already there isn't downloaded.
            setLastHandled(current?.uploadedAt ?: EMPTY_SLOT)
        } else if (current != null && current.sourceDeviceId != deviceId &&
            current.uploadedAt != lastHandled
        ) {
            setLastHandled(current.uploadedAt)
            when {
                current.isText -> copyText(current)
                current.isBundle -> saveBundle(current)
                else -> saveCopyAndNotify(current)
            }
        }
        current
    }

    /** After pairing: whatever is already in the slot isn't downloaded. */
    fun forgetLastHandled() = setLastHandled(null)

    private fun setLastHandled(uploadedAt: String?) {
        prefs.edit().putString(KEY_LAST_HANDLED, uploadedAt).apply()
    }

    private suspend fun saveCopyAndNotify(file: CurrentFile) {
        try {
            val saved =
                saveToPublicStorage(file.originalName, file.mimeType) {
                    backend.downloadToStream(it)
                }
            // Writing the clipboard from the background works on the phones
            // tested (#37). Where it's refused, the notification offers a tap.
            val clipped = withContext(Dispatchers.Main) {
                runCatching {
                    val clip = ClipData.newUri(ctx.contentResolver, file.originalName, saved.uri)
                    val manager = ctx.getSystemService(
                        Context.CLIPBOARD_SERVICE
                    ) as ClipboardManager
                    manager.setPrimaryClip(clip)
                    true
                }.getOrDefault(false)
            }
            MoxNotifications.showFileSaved(
                ctx,
                file.originalName,
                file.sizeBytes,
                saved.uri,
                file.mimeType,
                from = file.sourceName,
                savedTo = saved.locationLabel,
                copiedToClipboard = clipped
            )
        } catch (e: Exception) {
            android.util.Log.w("Mox", "Auto-save failed: ${e.message}")
        }
    }

    /**
     * Several files (#20): each one goes where a single file of its type
     * would, photos and videos in the gallery, and all of them on the clipboard.
     */
    private suspend fun saveBundle(item: CurrentFile) {
        try {
            val buffer = java.io.ByteArrayOutputStream()
            backend.downloadToStream(buffer)
            val entries = withContext(Dispatchers.Default) { Bundles.read(buffer.toByteArray()) }
            val saved = entries.map { entry ->
                val mime = android.webkit.MimeTypeMap.getSingleton()
                    .getMimeTypeFromExtension(entry.name.substringAfterLast('.', "").lowercase())
                saveToPublicStorage(entry.name, mime) { it.write(entry.data) }
            }
            val clipped = withContext(Dispatchers.Main) {
                runCatching {
                    val clip = ClipData.newUri(ctx.contentResolver, item.label, saved[0].uri)
                    saved.drop(1).forEach { clip.addItem(ClipData.Item(it.uri)) }
                    val manager = ctx.getSystemService(
                        Context.CLIPBOARD_SERVICE
                    ) as ClipboardManager
                    manager.setPrimaryClip(clip)
                    true
                }.getOrDefault(false)
            }
            val places = saved.map { it.locationLabel }.distinct().joinToString(" and ")
            MoxNotifications.showBundleSaved(ctx, item.label, item.sourceName, places, clipped)
        } catch (e: Exception) {
            android.util.Log.w("Mox", "Receiving ${item.label} failed: ${e.message}")
        }
    }

    /** A text goes on the clipboard as text, and no file is saved (#101). */
    private suspend fun copyText(item: CurrentFile) {
        try {
            val buffer = java.io.ByteArrayOutputStream()
            backend.downloadToStream(buffer)
            val text = TextPayload.decode(buffer.toByteArray())
            val clipped = withContext(Dispatchers.Main) {
                runCatching {
                    val manager = ctx.getSystemService(
                        Context.CLIPBOARD_SERVICE
                    ) as ClipboardManager
                    manager.setPrimaryClip(
                        ClipData.newPlainText("Text from ${item.sourceName}", text)
                    )
                    true
                }.getOrDefault(false)
            }
            MoxNotifications.showText(
                ctx,
                text,
                from = item.sourceName,
                copiedToClipboard = clipped
            )
        } catch (e: Exception) {
            android.util.Log.w("Mox", "Receiving text failed: ${e.message}")
        }
    }

    /** A saved file and a human-readable name for where it went. */
    private data class SavedFile(val uri: Uri, val locationLabel: String)

    /**
     * Saves a received file where the user expects it: photos and videos in
     * the Camera folder (visible in the gallery), everything else in
     * Downloads. See [SaveDestination].
     */
    private suspend fun saveToPublicStorage(
        name: String,
        mimeType: String?,
        write: suspend (java.io.OutputStream) -> Unit
    ): SavedFile = withContext(Dispatchers.IO) {
        val resolver = ctx.contentResolver
        if (Build.VERSION.SDK_INT < 29) {
            // Android 8–9 has no RELATIVE_PATH, and writing to shared folders
            // would need the storage permission. Keep the file in app
            // storage and share it through the FileProvider instead.
            val dir = File(ctx.cacheDir, "downloads").apply { mkdirs() }
            val out = File(dir, FileNames.sanitize(name))
            out.outputStream().use { write(it) }
            val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", out)
            return@withContext SavedFile(uri, locationLabel = "Mox")
        }
        val destination = SaveDestination.forMimeType(mimeType)
        val collection = when (destination) {
            SaveDestination.CAMERA_PHOTO -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            SaveDestination.CAMERA_VIDEO -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            SaveDestination.DOWNLOADS -> MediaStore.Downloads.EXTERNAL_CONTENT_URI
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, FileNames.sanitize(name))
            mimeType?.let { put(MediaStore.MediaColumns.MIME_TYPE, it) }
            put(MediaStore.MediaColumns.RELATIVE_PATH, destination.relativePath)
            // Hidden from other apps (the gallery included) until fully written.
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IOException("Couldn't create an entry in ${destination.label}")
        requireNotNull(resolver.openOutputStream(uri)) { "Can't write to ${destination.label}" }
            .use { write(it) }
        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        SavedFile(uri, destination.label)
    }

    companion object {
        const val PREFS = "mox"
        private const val KEY_LAST_HANDLED = "lastHandledUploadedAt"

        /** Baseline when the slot was empty on the first read (#71). */
        private const val EMPTY_SLOT = "empty"
        private val LOCK = Mutex()
    }
}
