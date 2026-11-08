package com.mox.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
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
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.mox.app.ui.MoxTheme

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
        setContent {
            MoxTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    val state by vm.state.collectAsState()
                    MoxScreen(state, onPull = { vm.saveAndShare() })
                }
            }
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
fun MoxScreen(state: UiState, onPull: () -> Unit) {
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
                "${humanBytes(file.sizeBytes)} · from ${file.uploadedFrom}",
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
