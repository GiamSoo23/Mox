package com.mox.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat

object MoxNotifications {
    const val CHANNEL_ID = "mox_files"
    const val CHANNEL_NAME = "Incoming files"
    private const val NOTIF_ID = 1001

    fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val mgr = ctx.getSystemService(NotificationManager::class.java)
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID, CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply { description = "Notifies when a file arrives from your other device" }
                mgr.createNotificationChannel(ch)
            }
        }
    }

    fun showFileSaved(ctx: Context, name: String, sizeBytes: Long, contentUri: Uri, mime: String?) {
        ensureChannel(ctx)
        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(contentUri, mime ?: "*/*")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val pi = PendingIntent.getActivity(
            ctx, name.hashCode(), view,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notif = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("New file from Mac")
            .setContentText("$name · saved to Downloads")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        ctx.getSystemService(NotificationManager::class.java).notify(NOTIF_ID, notif)
    }
}
