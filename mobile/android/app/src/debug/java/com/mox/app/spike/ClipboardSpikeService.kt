package com.mox.app.spike

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import com.mox.app.MoxNotifications
import com.mox.app.R

/**
 * Test 2: a foreground service (the way Mox would receive with the app
 * closed). Started with `adb shell am start-foreground-service`; copies
 * after `delay` seconds so there's time to switch to another app.
 */
class ClipboardSpikeService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        MoxNotifications.ensureChannel(this)
        val notification = NotificationCompat.Builder(this, MoxNotifications.CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Mox spike")
            .setContentText("Listening (clipboard test)")
            .build()
        startForeground(
            SPIKE_NOTIFICATION_ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        )

        val uri = intent?.getStringExtra("uri")
        val delaySeconds =
            intent?.getIntExtra("delay", DEFAULT_DELAY_SECONDS) ?: DEFAULT_DELAY_SECONDS
        Log.i("MoxSpike", "[service] started, copying in ${delaySeconds}s")
        Handler(Looper.getMainLooper()).postDelayed({
            ClipboardSpike.copy(this, uri, source = "service")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }, delaySeconds * 1000L)
        return START_NOT_STICKY
    }

    private companion object {
        const val SPIKE_NOTIFICATION_ID = 4242
        const val DEFAULT_DELAY_SECONDS = 10
    }
}
