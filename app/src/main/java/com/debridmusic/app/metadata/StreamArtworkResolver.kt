package com.debridmusic.app.metadata

import com.debridmusic.app.data.remote.api.DeezerApi
import com.debridmusic.app.data.remote.dto.bestCover
import com.debridmusic.app.data.remote.dto.bestImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Resolves cover art for streamed/synthetic tracks (TorBox/Soulseek) that have no
 * embedded artwork, using the keyless Deezer API. Memoized so an album queue only
 * hits the network once. Best-effort: returns null on any failure.
 */
@Singleton
class StreamArtworkResolver @Inject constructor(
    private val deezerApi: DeezerApi,
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
            }.getOrNull()
            if (found != null) memo[key] = found
            found
        }
}
