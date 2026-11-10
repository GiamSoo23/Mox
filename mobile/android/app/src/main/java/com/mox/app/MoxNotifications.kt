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
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply { description = "Notifies when a file arrives from your other device" }
                mgr.createNotificationChannel(ch)
            }
        }
    }

    fun showFileSaved(
        ctx: Context,
        name: String,
        sizeBytes: Long,
        contentUri: Uri,
        mime: String?,
        from: String,
        savedTo: String,
        copiedToClipboard: Boolean = false
    ) {
        ensureChannel(ctx)
        // Tap → run CopyToClipboardActivity (transparent, one-frame foreground)
        // so setPrimaryClip succeeds under Android 10+ background restrictions.
        val copy = Intent(ctx, CopyToClipboardActivity::class.java).apply {
            putExtra(CopyToClipboardActivity.EXTRA_URI, contentUri)
            putExtra(CopyToClipboardActivity.EXTRA_LABEL, name)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val pi = PendingIntent.getActivity(
            ctx,
            name.hashCode(),
            copy,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val body = if (copiedToClipboard) {
            "$name · in clipboard · saved to $savedTo"
        } else {
            "$name · tap to copy · saved to $savedTo"
        }
        val notif = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("New file from $from")
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        ctx.getSystemService(NotificationManager::class.java).notify(NOTIF_ID, notif)
    }

    /** A text arrived: show it, and offer a tap to copy where the background copy was refused. */
    fun showText(ctx: Context, text: String, from: String, copiedToClipboard: Boolean) {
        ensureChannel(ctx)
        val copy = Intent(ctx, CopyToClipboardActivity::class.java).apply {
            putExtra(CopyToClipboardActivity.EXTRA_TEXT, text)
            putExtra(CopyToClipboardActivity.EXTRA_LABEL, "Text from $from")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val pi = PendingIntent.getActivity(
            ctx,
            TEXT_NOTIF_ID,
            copy,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val preview = TextPayload.preview(text)
        val notif = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(
                "Text from $from · ${if (copiedToClipboard) "in clipboard" else "tap to copy"}"
            )
            .setContentText(preview)
            .setStyle(NotificationCompat.BigTextStyle().bigText(preview))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        ctx.getSystemService(NotificationManager::class.java).notify(TEXT_NOTIF_ID, notif)
    }

    private const val TEXT_NOTIF_ID = 1003
}
