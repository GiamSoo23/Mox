package com.mox.app

import android.app.Application
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import java.io.File
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

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
    private val deviceId: String = DeviceIdentity.id(app)

    private var repo: MoxBackend? = store.load()?.let { SupabaseRepo(it, deviceId) }
    private var receiver: FileReceiver? = repo?.let { FileReceiver(app, it, deviceId) }

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
        receiver =
            FileReceiver(getApplication(), candidate, deviceId).also { it.forgetLastHandled() }
        ListeningService.start(getApplication())
        _messages.tryEmit("Paired with ${parsed.desktopName ?: "your computer"}")
        refreshOnce()
        startPolling()
    }

    fun startPolling() {
        if (repo == null) return
        // Also covers phones paired before the service existed.
        ListeningService.start(getApplication())
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
        val check = receiver ?: return
        try {
            val current = check.check()
            _state.value = if (current == null) UiState.Empty() else UiState.Ready(current)
        } catch (e: Exception) {
            if (_state.value is UiState.Loading) {
                _state.value = UiState.Empty(error = e.message)
            }
            // Otherwise keep the last good state.
        }
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

    /** Sends plain text shared from another app (#101). */
    fun uploadText(text: String) = viewModelScope.launch {
        val backend = repo ?: run {
            _state.value = UiState.Error(NOT_PAIRED_MESSAGE)
            return@launch
        }
        _state.value = UiState.Uploading("text")
        try {
            _state.value = UiState.Sent(backend.uploadText(text))
        } catch (e: Exception) {
            _state.value = UiState.Error(e.message ?: "Couldn't send the text")
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
        const val NOT_PAIRED_MESSAGE =
            "Pair Mox with your computer first: open Mox there, choose Pair a Phone, and scan the code."
    }
}
