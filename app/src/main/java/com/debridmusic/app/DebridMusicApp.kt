package com.debridmusic.app

import android.app.Application
import com.debridmusic.app.data.repository.MusicRepository
import dagger.hilt.android.HiltAndroidApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltAndroidApp
class DebridMusicApp : Application() {

    @Inject lateinit var musicRepository: MusicRepository
    @Inject lateinit var appScope: CoroutineScope

    override fun onCreate() {
        // Install the crash reporter as early as possible so even a failure during
        // Hilt initialization (in super.onCreate) is captured and shown.
        CrashReporter.install(this)
        super.onCreate()
        // Auto-enrich an existing library on launch (non-blocking, off the main thread).
        appScope.launch {
            runCatching {
                if (musicRepository.trackCount().first() > 0) {
                    // Remove orphan (track-less) albums, fill cover-less tracks from their
                    // album cover immediately, then do the slower online metadata pass.
                    musicRepository.cleanupEmptyAlbumsInBackground()
                    musicRepository.backfillArtworkInBackground()
                    musicRepository.enrichInBackground()
                }
            }
        }
    }
}
