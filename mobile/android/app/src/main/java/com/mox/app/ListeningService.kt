package com.mox.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import kotlin.math.min
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

/**
 * Receives files with Mox closed (#37, DESIGN.md §3.1): a foreground service
 * holding one Realtime connection. Mox has no server, so Firebase push isn't
 * an option. On a change it reads the slot and receives the file.
 */
class ListeningService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var loop: Job? = null
    private var listeningTo: MoxSettings? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val type = if (Build.VERSION.SDK_INT >=
            34
        ) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else {
            0
        }
        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification(), type)
        val settings = SettingsStore(this).load()
        if (settings == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (settings != listeningTo || loop?.isActive != true) {
            listeningTo = settings
            loop?.cancel()
            loop = scope.launch { listen(settings) }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private suspend fun listen(settings: MoxSettings) {
        val deviceId = DeviceIdentity.id(this)
        val repo = SupabaseRepo(settings, deviceId)
        val receiver = FileReceiver(this, repo, deviceId)
        var wait = MIN_RETRY_MS
        while (scope.isActive) {
            try {
                connect(repo, receiver)
                wait = MIN_RETRY_MS
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                android.util.Log.w("Mox", "Listening failed: ${e.message}")
            }
            delay(wait)
            wait = min(wait * 2, MAX_RETRY_MS)
        }
    }

    /** One connection, until it drops or its token is about to expire. */
    private suspend fun connect(repo: SupabaseRepo, receiver: FileReceiver) = coroutineScope {
        val session = repo.realtimeSession()
        val changes = Channel<Unit>(Channel.CONFLATED)
        val closed = CompletableDeferred<Unit>()
        val socket = repo.openRealtime(
            session,
            object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    webSocket.send(RealtimeMessages.join(session.token))
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    if (RealtimeMessages.isChange(text)) changes.trySend(Unit)
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    closed.complete(Unit)
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    closed.complete(Unit)
                }
            }
        )
        val heartbeat = launch {
            var ref = 2
            while (isActive) {
                delay(HEARTBEAT_MS)
                socket.send(RealtimeMessages.heartbeat(ref++))
            }
        }
        // Reads on every (re)connection, because events sent while
        // disconnected are lost, and now and then in case an event is missed.
        val reader = launch {
            while (isActive) {
                runCatching { receiver.check() }
                    .onFailure { if (it is CancellationException) throw it }
                withTimeoutOrNull(SAFETY_READ_MS) { changes.receive() }
            }
        }
        withTimeoutOrNull(maxOf(session.validForMs - RENEW_EARLY_MS, RENEW_EARLY_MS)) {
            closed.await()
        }
        heartbeat.cancel()
        reader.cancel()
        socket.cancel()
    }

    private fun notification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Listening for files",
                    NotificationManager.IMPORTANCE_LOW
                )
                    .apply { description = "Keeps Mox ready to receive files with the app closed" }
            )
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Mox is listening")
            .setContentText("Files from your computer arrive here automatically.")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(open)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "mox_listening"
        private const val NOTIFICATION_ID = 1002
        private const val HEARTBEAT_MS = 25_000L
        private const val SAFETY_READ_MS = 5 * 60_000L
        private const val RENEW_EARLY_MS = 30_000L
        private const val MIN_RETRY_MS = 2_000L
        private const val MAX_RETRY_MS = 60_000L

        private const val KEY_ENABLED = "listeningEnabled"

        private fun prefs(context: Context) =
            context.getSharedPreferences(FileReceiver.PREFS, Context.MODE_PRIVATE)

        fun isEnabled(context: Context): Boolean = prefs(context).getBoolean(KEY_ENABLED, true)

        /** The switch on the main screen. Remembered across restarts. */
        fun setEnabled(context: Context, enabled: Boolean) {
            prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
            if (enabled) {
                start(context)
            } else {
                context.stopService(Intent(context, ListeningService::class.java))
            }
        }

        /** True when Android may stop the service to save battery. */
        fun batteryRestricted(context: Context): Boolean =
            !context.getSystemService(PowerManager::class.java)
                .isIgnoringBatteryOptimizations(context.packageName)

        /** Android's own "allow in the background" dialog. */
        fun requestBatteryExemption(context: Context) {
            context.startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:${context.packageName}")
                )
            )
        }

        /** Starts listening if Mox is paired and it's on. Safe to call repeatedly. */
        fun start(context: Context) {
            if (!isEnabled(context) || SettingsStore(context).load() == null) return
            runCatching {
                ContextCompat.startForegroundService(
                    context,
                    Intent(context, ListeningService::class.java)
                )
            }.onFailure { android.util.Log.w("Mox", "Couldn't start listening: ${it.message}") }
        }
    }
}

/** Resumes listening after the phone restarts or Mox is updated. */
class ListeningStarter : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            ListeningService.start(context)
        }
    }
}
