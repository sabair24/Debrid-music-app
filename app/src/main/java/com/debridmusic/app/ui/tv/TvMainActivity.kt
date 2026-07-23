package com.debridmusic.app.ui.tv

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.debridmusic.app.cast.CastReceiverService
import com.debridmusic.app.cast.CastRequest
import com.debridmusic.app.player.PlayerController
import com.debridmusic.app.ui.theme.DebridMusicTheme
import com.google.gson.Gson
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
class TvMainActivity : ComponentActivity() {

    @Inject lateinit var playerController: PlayerController

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Start listening for "play this here" from the Mac and the iPad. Idempotent, so opening
        // the app after a reboot simply finds the service already running.
        CastReceiverService.startIfTv(this)
        setContent {
            DebridMusicTheme {
                TvApp()
            }
        }
        handleCast(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleCast(intent)
    }

    /**
     * A cast that arrived while the app was closed or in the background.
     *
     * The controller may not have connected yet when this runs on a cold start, so playback is
     * posted rather than called straight away — otherwise the very first cast after a reboot,
     * which is exactly the one that has to work, is the one that gets dropped.
     */
    private fun handleCast(intent: Intent?) {
        if (intent?.action != CastReceiverService.ACTION_PLAY) return
        val json = intent.getStringExtra(CastReceiverService.EXTRA_REQUEST) ?: return
        val request = runCatching { Gson().fromJson(json, CastRequest::class.java) }.getOrNull() ?: return
        if (request.streamUrls.isEmpty()) return
        // Clear it, or rotating the TV or coming back from the launcher replays the same cast.
        intent.action = null

        playerController.connect()
        window.decorView.postDelayed({
            playerController.playRemoteQueue(
                urls = request.streamUrls,
                startIndex = request.index,
                startMs = request.startMs,
                title = request.title,
                artist = request.artist,
                album = request.album,
                artworkUri = request.artUrl,
            )
        }, 600)
    }
}
