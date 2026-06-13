package com.debridmusic.app.soulseek

import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.metadata.MetadataEnricher
import com.debridmusic.app.scanner.MediaScanner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SoulseekRepository @Inject constructor(
    private val client: SoulseekClient,
    private val settingsStore: SettingsStore,
    private val libraryPublisher: LibraryPublisher,
    private val mediaScanner: MediaScanner,
    private val metadataEnricher: MetadataEnricher,
    private val appScope: CoroutineScope,
) {
    private suspend fun credentials(): Pair<String, String> {
        val username = settingsStore.slskUsername.first()
        val password = settingsStore.slskPassword.first()
        if (username.isBlank()) error("Soulseek username not configured — add it in Settings")
        if (password.isBlank()) error("Soulseek password not configured — add it in Settings")
        return username to password
    }

    suspend fun search(query: String): Result<List<SoulseekFile>> {
        val creds = runCatching { credentials() }.getOrElse { return Result.failure(it) }
        return client.search(creds.first, creds.second, query)
    }

    suspend fun testLogin(username: String, password: String): Result<Unit> =
        client.testLogin(username, password)

    fun download(file: SoulseekFile): Flow<SlskDownloadState> = flow {
        val (username, password) = credentials()
        client.download(username, password, file).collect { state ->
            if (state is SlskDownloadState.Done) {
                // Parse real artist/album/title from the Soulseek folder path so the
                // track lands in the library with usable tags (not the uploader name).
                val meta = SoulseekPath.parse(file.filename)
                val publishedUri = runCatching {
                    libraryPublisher.publish(
                        tempPath = state.localPath,
                        originalFileName = file.displayName,
                        title = meta.title,
                        artist = meta.artist,
                        album = meta.album,
                    )
                }.getOrNull()
                // Import into the in-app library, then enrich (cover art, album,
                // artist) in the background so the Done state isn't blocked.
                runCatching { mediaScanner.scanDevice() }
                appScope.launch { runCatching { metadataEnricher.enrichAll() } }
                emit(SlskDownloadState.Done(publishedUri ?: state.localPath))
            } else {
                emit(state)
            }
        }
    }.catch { e -> emit(SlskDownloadState.Error(e.message ?: "Download failed")) }
}
