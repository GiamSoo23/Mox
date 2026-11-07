package com.mox.app

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.widget.Toast

/// Background apps can't reliably write the system clipboard on Android 10+
/// (Samsung enforces this hard). This transparent, single-frame activity
/// gives us one tick of foreground state — just enough to call
/// `setPrimaryClip` so the keyboard's clipboard chip picks up the file.
class CopyToClipboardActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri: Uri? = intent.getParcelableExtra(EXTRA_URI)
        val label = intent.getStringExtra(EXTRA_LABEL) ?: "Mox file"
        if (uri != null) {
            runCatching {
                val clip = ClipData.newUri(contentResolver, label, uri)
                val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(clip)
                Toast.makeText(this, "Copied — paste with the keyboard", Toast.LENGTH_SHORT).show()
            }.onFailure {
                Toast.makeText(this, "Couldn't copy: ${it.message}", Toast.LENGTH_LONG).show()
            }
        }
        finish()
    }

    companion object {
        const val EXTRA_URI = "mox.uri"
        const val EXTRA_LABEL = "mox.label"
    }
}
