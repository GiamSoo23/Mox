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
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

sealed class UiState {
    object Loading : UiState()

    /** No settings yet: the user has to scan the desktop's QR code (or paste the link). */
    data class NotPaired(val error: String? = null) : UiState()
    data class Empty(val error: String? = null) : UiState()
    data class Ready(val file: CurrentFile, val downloadedTo: File? = null) : UiState()
    data class Uploading(val name: String) : UiState()
    data class Sent(val file: CurrentFile) : UiState()
    data class Error(val message: String) : UiState()
}

class MoxViewModel(app: Application) : AndroidViewModel(app) {
    private val store = SettingsStore(app)
    private val prefs = app.getSharedPreferences("mox", Context.MODE_PRIVATE)

    /** This installation's id (PROTOCOL.md §1), written into every row it sends. */
    private val deviceId: String = prefs.getString(KEY_DEVICE_ID, null)
        ?: UUID.randomUUID().toString().also { prefs.edit().putString(KEY_DEVICE_ID, it).apply() }

    private var repo: MoxBackend? = store.load()?.let { SupabaseRepo(it, deviceId) }

    /** uploaded_at of the last file handled, kept across launches (PROTOCOL.md §6). */
    private var lastHandled: String? = prefs.getString(KEY_LAST_HANDLED, null)

    private val _state = MutableStateFlow<UiState>(
        if (repo ==
            null
        ) {
            UiState.NotPaired()
        } else {
            UiState.Loading
        }
    )
    val state: StateFlow<UiState> = _state.asStateFlow()

    /** Short messages for a toast, e.g. "Paired with Gregory's MacBook". */
    private val _messages = MutableSharedFlow<String>(extraBufferCapacity = 4)
    val messages: SharedFlow<String> = _messages.asSharedFlow()

    private var pollJob: Job? = null

    /**
     * Pairs with a desktop from a pairing link (PROTOCOL.md §8.3): parse it,
     * sign in and check the schema, and only then store the settings.
     */
    fun pair(link: String) = viewModelScope.launch {
        val parsed = try {
            PairingLink.parse(link)
        } catch (e: PairingException) {
            _state.value = UiState.NotPaired(e.message)
            return@launch
        }
        val candidate = SupabaseRepo(parsed.toSettings(), deviceId)
        _state.value = UiState.Loading
        try {
            candidate.checkSchema()
        } catch (e: Exception) {
            _state.value = UiState.NotPaired(e.message ?: "Pairing failed. Scan the QR code again.")
            return@launch
        }
        store.save(parsed.toSettings())
        repo = candidate
        // A fresh pairing doesn't download whatever is already in the slot.
        setLastHandled(null)
        _messages.tryEmit("Paired with ${parsed.desktopName ?: "your computer"}")
        refreshOnce()
        startPolling()
    }

    fun startPolling() {
        if (repo == null || pollJob?.isActive == true) return
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
        val backend = repo ?: return
        try {
            val current = backend.fetchCurrent()
            _state.value = if (current == null) UiState.Empty() else UiState.Ready(current)
            if (current != null) receiveIfNew(current)
        } catch (e: Exception) {
            if (_state.value is UiState.Loading) {
                _state.value = UiState.Empty(error = e.message)
            }
            // Otherwise keep the last good state.
        }
    }

    /** PROTOCOL.md §6: skip our own uploads and files already handled. */
    private suspend fun receiveIfNew(file: CurrentFile) {
        if (file.sourceDeviceId == deviceId) return
        val last = lastHandled
        if (last == null) {
            // First run or fresh pairing: remember what's there, don't download it.
            setLastHandled(file.uploadedAt)
            return
        }
        if (file.uploadedAt == last) return
        setLastHandled(file.uploadedAt)
        autoSaveAndNotify(file)
    }

    private fun setLastHandled(uploadedAt: String?) {
        lastHandled = uploadedAt
        prefs.edit().putString(KEY_LAST_HANDLED, uploadedAt).apply()
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
                from = file.sourceName,
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
                val out = File(dir, FileNames.sanitize(file.originalName))
                out.outputStream().use { requireRepo().downloadToStream(it) }
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
                put(MediaStore.MediaColumns.DISPLAY_NAME, FileNames.sanitize(file.originalName))
                file.mimeType?.let { put(MediaStore.MediaColumns.MIME_TYPE, it) }
                put(MediaStore.MediaColumns.RELATIVE_PATH, destination.relativePath)
                // Hidden from other apps (the gallery included) until fully written.
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(collection, values)
                ?: throw IOException("Couldn't create an entry in ${destination.label}")
            requireNotNull(resolver.openOutputStream(uri)) {
                "Can't write to ${destination.label}"
            }.use { out ->
                requireRepo().downloadToStream(out)
            }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            SavedFile(uri, destination.label)
        }

    fun upload(uri: Uri) = viewModelScope.launch {
        val backend = repo ?: run {
            _state.value = UiState.Error(NOT_PAIRED_MESSAGE)
            return@launch
        }
        val resolver = getApplication<Application>().contentResolver
        val (name, size, mime) = describe(resolver, uri)
        _state.value = UiState.Uploading(name)
        try {
            val row = backend.uploadFromContentUri(resolver, uri, name, size, mime)
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
            val safe = FileNames.sanitize(s.file.originalName)
            val outFile = File(dir, safe)
            requireRepo().downloadTo(outFile)
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

    private fun requireRepo(): MoxBackend = repo ?: throw MoxException(NOT_PAIRED_MESSAGE)

    private companion object {
        const val KEY_DEVICE_ID = "deviceId"
        const val KEY_LAST_HANDLED = "lastHandledUploadedAt"
        const val NOT_PAIRED_MESSAGE =
            "Pair Mox with your computer first: open Mox there, choose Pair a Phone, and scan the code."
    }
}
