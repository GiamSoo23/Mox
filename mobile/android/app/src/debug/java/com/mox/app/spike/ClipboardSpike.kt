package com.mox.app.spike

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.util.Log

/**
 * Spike for #37: can Mox write the clipboard while another app is in front?
 * Debug builds only. Results are read from logcat (tag "MoxSpike") and by
 * pasting in another app.
 */
object ClipboardSpike {
    private const val TAG = "MoxSpike"

    fun copy(context: Context, uri: String?, source: String) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = if (uri != null) {
            ClipData.newUri(context.contentResolver, "Mox spike", Uri.parse(uri))
        } else {
            ClipData.newPlainText(
                "Mox spike",
                "Mox spike from $source at ${System.currentTimeMillis()}"
            )
        }
        runCatching { clipboard.setPrimaryClip(clip) }
            .onSuccess { Log.i(TAG, "[$source] setPrimaryClip returned normally (uri=$uri)") }
            .onFailure { Log.e(TAG, "[$source] setPrimaryClip threw", it) }
    }
}
