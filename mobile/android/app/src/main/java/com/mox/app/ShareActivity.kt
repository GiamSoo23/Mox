package com.mox.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.mox.app.ui.MoxTheme

/**
 * Receives ACTION_SEND and ACTION_SEND_MULTIPLE from other apps (Gallery,
 * WhatsApp, browsers, …). One file goes as is, several as a bundle (#20).
 */
class ShareActivity : ComponentActivity() {
    private val vm: MoxViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val uris = extractUris(intent)
        // Plain text shared from another app, such as a link or a note (#101).
        val text = if (uris.isEmpty()) intent.getStringExtra(Intent.EXTRA_TEXT) else null
        if (uris.isEmpty() && text.isNullOrBlank()) {
            Toast.makeText(this, "Mox: nothing to send.", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        setContent {
            MoxTheme {
                val state by vm.state.collectAsState()
                Dialog(
                    onDismissRequest = { finish() },
                    properties = DialogProperties(
                        dismissOnClickOutside = false,
                        dismissOnBackPress = state !is UiState.Uploading
                    )
                ) {
                    Surface(
                        shape = MaterialTheme.shapes.large,
                        color = MaterialTheme.colorScheme.surface
                    ) {
                        ShareSheet(state, onDone = { finish() })
                    }
                }
            }
        }

        when {
            uris.size > 1 -> vm.uploadMany(uris)
            uris.size == 1 -> vm.upload(uris[0])
            else -> vm.uploadText(text!!)
        }
    }

    private fun extractUris(intent: Intent): List<Uri> {
        if (intent.action == Intent.ACTION_SEND) {
            return listOfNotNull(
                if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
            )
        }
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            val list = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }
            return list.orEmpty().filterNotNull().distinct()
        }
        return emptyList()
    }
}

@Composable
private fun ShareSheet(state: UiState, onDone: () -> Unit) {
    Column(
        Modifier.padding(24.dp).widthIn(min = 240.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("Mox", style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(16.dp))
        when (state) {
            is UiState.Uploading -> {
                CircularProgressIndicator()
                Spacer(Modifier.height(12.dp))
                Text(
                    "Sending ${state.name}",
                    style = MaterialTheme.typography.bodyMedium
                )
            }

            is UiState.Sent -> {
                Text("Sent ✓", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(4.dp))
                Text(
                    state.file.label,
                    style = MaterialTheme.typography.bodySmall
                )
                Spacer(Modifier.height(16.dp))
                TextButton(onDone) { Text("Done") }
                LaunchedEffect(state) {
                    kotlinx.coroutines.delay(900)
                    onDone()
                }
            }

            is UiState.Error -> {
                Text("Couldn't send", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(4.dp))
                Text(state.message, style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.height(16.dp))
                TextButton(onDone) { Text("Close") }
            }

            else -> {
                CircularProgressIndicator()
            }
        }
    }
}
