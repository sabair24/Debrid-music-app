package com.debridmusic.app.metadata

import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.remote.DiscogsAuthInterceptor
import com.debridmusic.app.data.remote.api.DeezerApi
import com.debridmusic.app.data.remote.api.DiscogsApi
import com.debridmusic.app.data.remote.dto.bestCover
import com.debridmusic.app.data.remote.dto.bestImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Resolves cover art for streamed/synthetic tracks (TorBox/Soulseek) that have no
 * embedded artwork. Tries the keyless Deezer API first, then falls back to Discogs
 * if the user configured a token. Memoized so an album queue only hits the network
 * once. Best-effort: returns null on any failure.
 */
@Singleton
class StreamArtworkResolver @Inject constructor(
    private val deezerApi: DeezerApi,
    private val discogsApi: DiscogsApi,
    private val discogsAuth: DiscogsAuthInterceptor,
    private val settingsStore: SettingsStore,
) {
    private val memo = ConcurrentHashMap<String, String>()

    suspend fun resolve(artist: String, title: String, album: String): String? =
        withContext(Dispatchers.IO) {
            val key = "${artist.lowercase()}|${album.lowercase()}|${title.lowercase()}"
            memo[key]?.let { return@withContext it }
            val found = runCatching {
                // Prefer an album cover; fall back to the artist image.
                val q = listOf(album, artist).filter { it.isNotBlank() }.joinToString(" ").ifBlank { title }
                deezerApi.searchAlbum(q).data?.firstOrNull()?.bestCover()
                    ?: deezerApi.searchArtist(artist).data?.firstOrNull()?.bestImage()
                    ?: resolveFromDiscogs(artist, album)
            }.getOrNull()
            if (found != null) memo[key] = found
            found
        }

    private suspend fun resolveFromDiscogs(artist: String, album: String): String? {
        val token = settingsStore.discogsToken.first()
        if (token.isBlank() || album.isBlank()) return null
        discogsAuth.token = token
        return runCatching {
            discogsApi.searchRelease(album, artist).results?.firstNotNullOfOrNull { it.bestImage() }
        }.getOrNull()
    }
}
