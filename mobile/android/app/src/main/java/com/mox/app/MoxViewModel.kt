package com.mox.app

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import java.io.File
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

sealed class UiState {
    object Loading : UiState()
    data class Empty(val error: String? = null) : UiState()
    data class Ready(val file: CurrentFile, val downloadedTo: File? = null) : UiState()
    data class Uploading(val name: String) : UiState()
    data class Sent(val file: CurrentFile) : UiState()
    data class Error(val message: String) : UiState()
}

class MoxViewModel(app: Application) : AndroidViewModel(app) {
    private val repo: MoxBackend = SupabaseRepo()
    private val _state = MutableStateFlow<UiState>(UiState.Loading)
    val state: StateFlow<UiState> = _state.asStateFlow()
    private var pollJob: Job? = null

    // Persisted across launches so we don't re-notify or re-download the
    // same file every time the user opens the app.
    private val prefs = app.getSharedPreferences("mox", android.content.Context.MODE_PRIVATE)
    private var lastHandledKey: String? = prefs.getString("lastHandledKey", null)

    fun startPolling() {
        if (pollJob?.isActive == true) return
        pollJob = viewModelScope.launch {
            while (true) {
                refreshOnce()
                delay(Config.POLL_MS)
            }
        }
    }

    fun stopPolling() {
        pollJob?.cancel()
        pollJob = null
    }

    private suspend fun refreshOnce() {
        try {
            val current = repo.fetchCurrent()
            _state.value = if (current == null) {
                UiState.Empty()
            } else {
                UiState.Ready(current)
            }
            if (current != null && current.uploadedFrom != "android") {
                val key = "${current.storagePath}|${current.uploadedAt}"
                if (key != lastHandledKey) {
                    lastHandledKey = key
                    prefs.edit().putString("lastHandledKey", key).apply()
                    autoSaveAndNotify(current)
                }
            }
        } catch (e: Exception) {
            if (_state.value is UiState.Loading) {
                _state.value = UiState.Empty(error = e.message)
            }
            // Otherwise keep the last good state.
        }
    }

    private suspend fun autoSaveAndNotify(file: CurrentFile) {
        try {
            val ctx = getApplication<Application>()
            val saved = saveToPublicStorage(file)
            val uri = saved.uri
            // Best-effort clipboard set — only succeeds if Mox is foregrounded
            // (Android 10+ blocks background clipboard writes). The notification
            // tap routes through CopyToClipboardActivity for the common case.
            val clipped = withContext(Dispatchers.Main) {
                runCatching {
                    val clip = ClipData.newUri(ctx.contentResolver, file.originalName, uri)
                    val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(clip)
                    true
                }.getOrDefault(false)
            }
            MoxNotifications.showFileSaved(
                ctx,
                file.originalName,
                file.sizeBytes,
                uri,
                file.mimeType,
                savedTo = saved.locationLabel,
                copiedToClipboard = clipped
            )
        } catch (e: Exception) {
            // Surface error but don't blow up state — keep last good UI.
            android.util.Log.w("Mox", "Auto-save failed: ${e.message}")
        }
    }

    /** A saved file and a human-readable name for where it went. */
    private data class SavedFile(val uri: Uri, val locationLabel: String)

    /**
     * Saves a received file where the user expects it: photos and videos in
     * the Camera folder (visible in the gallery), everything else in
     * Downloads. See [SaveDestination].
     */
    private suspend fun saveToPublicStorage(file: CurrentFile): SavedFile =
        withContext(Dispatchers.IO) {
            val ctx = getApplication<Application>()
            val resolver = ctx.contentResolver
            if (Build.VERSION.SDK_INT < 29) {
                // Android 8–9 has no RELATIVE_PATH, and writing to shared folders
                // would need the storage permission. Keep the file in app
                // storage and share it through the FileProvider instead.
                val dir = File(ctx.cacheDir, "downloads").apply { mkdirs() }
                val out = File(dir, sanitize(file.originalName))
                out.outputStream().use { repo.downloadToStream(it, file) }
                val uri = FileProvider.getUriForFile(
                    ctx,
                    "${ctx.packageName}.fileprovider",
                    out
                )
                return@withContext SavedFile(uri, locationLabel = "Mox")
            }
            val destination = SaveDestination.forMimeType(file.mimeType)
            val collection = when (destination) {
                SaveDestination.CAMERA_PHOTO -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                SaveDestination.CAMERA_VIDEO -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                SaveDestination.DOWNLOADS -> MediaStore.Downloads.EXTERNAL_CONTENT_URI
            }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, sanitize(file.originalName))
                file.mimeType?.let { put(MediaStore.MediaColumns.MIME_TYPE, it) }
                put(MediaStore.MediaColumns.RELATIVE_PATH, destination.relativePath)
                // Hidden from other apps (the gallery included) until fully written.
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(collection, values)
                ?: throw IOException("Couldn't create an entry in ${destination.label}")
            resolver.openOutputStream(uri)!!.use { out ->
                repo.downloadToStream(out, file)
            }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            SavedFile(uri, destination.label)
        }

    private fun sanitize(name: String): String = name.replace("[^A-Za-z0-9._-]".toRegex(), "_")

    fun upload(uri: Uri) = viewModelScope.launch {
        val resolver = getApplication<Application>().contentResolver
        val (name, size, mime) = describe(resolver, uri)
        _state.value = UiState.Uploading(name)
        try {
            val row = repo.uploadFromContentUri(resolver, uri, name, size, mime)
            _state.value = UiState.Sent(row)
        } catch (e: Exception) {
            _state.value = UiState.Error(e.message ?: "Upload failed")
        }
    }

    fun saveAndShare() = viewModelScope.launch {
        val s = _state.value as? UiState.Ready ?: return@launch
        try {
            val app = getApplication<Application>()
            val dir = File(app.cacheDir, "downloads").apply { mkdirs() }
            val safe = s.file.originalName.replace("[^A-Za-z0-9._-]".toRegex(), "_")
            val outFile = File(dir, safe)
            repo.downloadTo(outFile, s.file)
            _state.value = UiState.Ready(s.file, downloadedTo = outFile)

            val shareUri: Uri = FileProvider.getUriForFile(
                app,
                "${app.packageName}.fileprovider",
                outFile
            )
            val share = Intent(Intent.ACTION_SEND).apply {
                type = s.file.mimeType ?: "*/*"
                putExtra(Intent.EXTRA_STREAM, shareUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            app.startActivity(
                Intent.createChooser(share, "Save / share").apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
        } catch (e: Exception) {
            _state.value = UiState.Error(e.message ?: "Download failed")
        }
    }

    private fun describe(cr: ContentResolver, uri: Uri): Triple<String, Long, String?> {
        var name = uri.lastPathSegment ?: "file"
        var size = -1L
        cr.query(uri, null, null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                val ni = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val si = c.getColumnIndex(OpenableColumns.SIZE)
                if (ni >= 0 && !c.isNull(ni)) name = c.getString(ni)
                if (si >= 0 && !c.isNull(si)) size = c.getLong(si)
            }
        }
        if (size <= 0) {
            cr.openFileDescriptor(uri, "r")?.use { size = it.statSize }
        }
        val mime = cr.getType(uri)
        return Triple(name, size, mime)
    }
}
