package com.mox.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material.icons.filled.InsertDriveFile
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.mox.app.ui.MoxTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val vm: MoxViewModel by viewModels()

    private val notifPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* ignore result — Mox still works without notifications */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        MoxNotifications.ensureChannel(this)
        if (Build.VERSION.SDK_INT >= 33) {
            val granted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) notifPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        handlePairingLink(intent)
        lifecycleScope.launch {
            vm.messages.collect { Toast.makeText(this@MainActivity, it, Toast.LENGTH_LONG).show() }
        }
        setContent {
            MoxTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    val state by vm.state.collectAsState()
                    MoxScreen(state, onPull = { vm.saveAndShare() }, onPair = { vm.pair(it) })
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handlePairingLink(intent)
    }

    /**
     * The pairing page opens Mox with mox://pair?<params> (PROTOCOL.md §8.1).
     * The raw, still-encoded string is parsed: Uri.getQueryParameter would
     * turn '+' into a space.
     */
    private fun handlePairingLink(intent: Intent?) {
        val link = intent?.dataString ?: return
        if (link.startsWith("mox://pair")) {
            vm.pair(link)
            // Don't pair again on rotation or when the activity is recreated.
            intent.data = null
        }
    }

    override fun onStart() {
        super.onStart()
        vm.startPolling()
    }
    override fun onStop() {
        super.onStop()
        vm.stopPolling()
    }
}

@Composable
fun MoxScreen(state: UiState, onPull: () -> Unit, onPair: (String) -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            "Mox",
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(Modifier.height(8.dp))
        Text(
            "One file, between devices",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(40.dp))

        when (state) {
            is UiState.Loading -> CircularProgressIndicator()

            is UiState.NotPaired -> PairCard(state.error, onPair)

            is UiState.Empty -> EmptyCard(state.error)

            is UiState.Ready -> FileCard(
                state.file,
                onPull = onPull,
                downloaded = state.downloadedTo != null
            )

            is UiState.Uploading -> StatusCard(
                icon = Icons.Filled.HourglassEmpty,
                title = "Sending…",
                subtitle = state.name
            )

            is UiState.Sent -> StatusCard(
                icon = Icons.Filled.InsertDriveFile,
                title = "Sent",
                subtitle = "${state.file.originalName} · ${humanBytes(state.file.sizeBytes)}"
            )

            is UiState.Error -> StatusCard(
                icon = Icons.Filled.InsertDriveFile,
                title = "Error",
                subtitle = state.message,
                tone = ToneError
            )
        }
    }
}

/**
 * Shown until the phone is paired. Scanning the desktop's QR code with the
 * camera opens the pairing page, which hands the link to this app. Pasting
 * the link here is the fallback.
 */
@Composable
private fun PairCard(error: String?, onPair: (String) -> Unit) {
    var link by remember { mutableStateOf("") }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(20.dp)) {
            Text(
                "Pair with your computer",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Medium
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "On your computer, open Mox and choose Pair a Phone. Then scan the code with your camera.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (error != null) {
                Spacer(Modifier.height(12.dp))
                Text(
                    error,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }
            Spacer(Modifier.height(16.dp))
            OutlinedTextField(
                value = link,
                onValueChange = { link = it },
                label = { Text("Or paste the pairing link") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            TextButton(onClick = { onPair(link) }, enabled = link.isNotBlank()) { Text("Pair") }
        }
    }
}

@Composable
private fun EmptyCard(error: String?) {
    StatusCard(
        icon = Icons.Filled.InsertDriveFile,
        title = "No file yet",
        subtitle = error ?: "Send one from your Mac, or share into Mox from any app."
    )
}

@Composable
private fun FileCard(file: CurrentFile, onPull: () -> Unit, downloaded: Boolean) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(20.dp)) {
            Text(
                file.originalName,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Medium
            )
            Spacer(Modifier.height(4.dp))
            Text(
                "${humanBytes(file.sizeBytes)} · from ${file.sourceName}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.height(20.dp))
            FilledTonalButton(
                onClick = onPull,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Filled.CloudDownload, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(if (downloaded) "Open / share again" else "Save / share")
            }
        }
    }
}

private enum class Tone { Normal, ErrorT }
private val ToneError = Tone.ErrorT

@Composable
private fun StatusCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String,
    tone: Tone = Tone.Normal
) {
    val container = if (tone == ToneError) {
        MaterialTheme.colorScheme.errorContainer
    } else {
        MaterialTheme.colorScheme.surfaceVariant
    }
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = container)
    ) {
        Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null)
            Spacer(Modifier.width(16.dp))
            Column {
                Text(
                    title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Medium
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
