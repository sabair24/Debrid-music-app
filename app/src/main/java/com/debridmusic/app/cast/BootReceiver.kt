package com.debridmusic.app.cast

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Brings the cast receiver back after the TV restarts.
 *
 * Without this, "play on the Shield" works until the first power cut and then quietly stops
 * working — and the reason would be invisible, because everything else about the app is fine.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }
        CastReceiverService.startIfTv(context)
    }
}
