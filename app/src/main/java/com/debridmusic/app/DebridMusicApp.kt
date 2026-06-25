package com.debridmusic.app

import android.app.Application
import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.repository.MusicRepository
import com.debridmusic.app.server.ServerRepository
import dagger.hilt.android.HiltAndroidApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltAndroidApp
class DebridMusicApp : Application() {

    @Inject lateinit var musicRepository: MusicRepository
    @Inject lateinit var serverRepository: ServerRepository
    @Inject lateinit var settingsStore: SettingsStore
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
        // Refresh the self-hosted music server catalog on launch (if configured).
        appScope.launch {
            runCatching {
                val url = settingsStore.serverUrl.first()
                val token = settingsStore.serverToken.first()
                if (url.isNotBlank()) {
                    serverRepository.configure(url, token)
                    val catalog = serverRepository.fetchCatalog()
                    musicRepository.syncServerLibrary(catalog, url, token)
                    settingsStore.setServerLastSync(System.currentTimeMillis())
                }
            }
        }
    }
}
