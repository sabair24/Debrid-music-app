package com.debridmusic.app.cast

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.debridmusic.app.R
import com.debridmusic.app.ui.tv.TvMainActivity
import com.google.gson.Gson

/**
 * Keeps the "play this on the Shield" listener alive.
 *
 * A foreground service rather than something the activity owns, because the point is to work when
 * the app is NOT open: you pick a record on the iPad in another room, and the TV starts playing.
 * An activity-scoped listener only works when someone already walked over and opened the app,
 * which defeats the feature.
 *
 * Handing the request to [TvMainActivity] instead of playing here is deliberate: the activity has
 * the connected MediaController and the UI, so what plays is also what you see. Launching an
 * activity from the background needs SYSTEM_ALERT_WINDOW — see the note in the manifest.
 */
class CastReceiverService : Service() {

    private var server: CastReceiverServer? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIFICATION_ID, notification())
        server = CastReceiverServer(
            onPlay = { request -> launchPlayback(request) },
            onStop = { sendBroadcast(Intent(ACTION_STOP).setPackage(packageName)) },
        ).also { it.start() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        server?.stop()
        server = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun launchPlayback(request: CastRequest) {
        val intent = Intent(this, TvMainActivity::class.java).apply {
            action = ACTION_PLAY
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(EXTRA_REQUEST, Gson().toJson(request))
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            // Without the background-launch exemption Android drops this silently. Say so here,
            // or the only symptom is a cast that "does nothing".
            Log.w(TAG, "could not bring the app forward — is SYSTEM_ALERT_WINDOW granted? ${e.message}")
        }
    }

    private fun notification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Afspelen op deze tv", NotificationManager.IMPORTANCE_MIN)
                    .apply { description = "Luistert of je Mac of iPad muziek naar deze tv stuurt." }
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("DebridMusic")
            .setContentText("Klaar om muziek van je Mac of iPad te ontvangen")
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val TAG = "CastReceiverService"
        private const val CHANNEL_ID = "cast_receiver"
        private const val NOTIFICATION_ID = 4711
        const val ACTION_PLAY = "com.debridmusic.app.CAST_PLAY"
        const val ACTION_STOP = "com.debridmusic.app.CAST_STOP"
        const val EXTRA_REQUEST = "cast_request"

        /** Only on a TV: a phone in your pocket is not something to send a record to. */
        fun startIfTv(context: Context) {
            if (!isTv(context)) return
            val intent = Intent(context, CastReceiverService::class.java)
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            }.onFailure { Log.w(TAG, "could not start the cast receiver: ${it.message}") }
        }

        fun isTv(context: Context): Boolean =
            context.packageManager.hasSystemFeature("android.software.leanback") ||
                context.packageManager.hasSystemFeature("android.hardware.type.television")
    }
}
