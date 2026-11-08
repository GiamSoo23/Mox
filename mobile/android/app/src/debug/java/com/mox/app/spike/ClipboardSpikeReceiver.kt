package com.mox.app.spike

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Test 1: plain background. Triggered with `adb shell am broadcast`. */
class ClipboardSpikeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ClipboardSpike.copy(context, intent.getStringExtra("uri"), source = "receiver")
    }
}
