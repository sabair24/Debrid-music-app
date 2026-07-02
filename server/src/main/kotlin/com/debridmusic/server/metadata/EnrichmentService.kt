package com.debridmusic.server.metadata

import com.debridmusic.server.index.IndexStore
import com.debridmusic.server.net.Http
import com.debridmusic.server.service.ArtworkService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import org.slf4j.LoggerFactory
import java.io.File
import java.net.URLEncoder

@Serializable
data class EnrichStatusDto(val running: Boolean, val done: Int, val total: Int, val fetched: Int)

@Serializable
private data class DeezerAlbumSearch(val data: List<DeezerAlbum> = emptyList())

@Serializable
private data class DeezerAlbum(
    val title: String? = null,
    @SerialName("cover_big") val coverBig: String? = null,
    @SerialName("cover_xl") val coverXl: String? = null,
)

/**
 * Fills in missing album cover art from Deezer (keyless) and caches it as
 * `<artCacheDir>/<albumId>.jpg`, which [ArtworkService] then serves. Idempotent:
 * albums that already have local or cached art are skipped, so it's safe to re-run.
 */
class EnrichmentService(
    private val store: IndexStore,
    private val artwork: ArtworkService,
    private val artCacheDir: File,
    private val appScope: CoroutineScope,
) {
    private val log = LoggerFactory.getLogger(EnrichmentService::class.java)
    private val mutex = Mutex()

    @Volatile private var running = false
    @Volatile private var done = 0
    @Volatile private var total = 0
    @Volatile private var fetched = 0

    fun status() = EnrichStatusDto(running, done, total, fetched)

    /** Kick off enrichment in the background (no-op if already running). */
    fun enrichInBackground() {
        appScope.launch { runCatching { enrichAll() }.onFailure { log.warn("enrich failed: {}", it.message) } }
    }

    suspend fun enrichAll() {
        if (!mutex.tryLock()) return
        try {
            running = true; done = 0; fetched = 0
            artCacheDir.mkdirs()
            val albums = store.albums()
            total = albums.size
            log.info("Enrichment: scanning {} albums for missing art…", total)
            for (a in albums) {
                done++
                val cache = File(artCacheDir, "${a.id}.jpg")
                if (cache.isFile || artwork.hasLocalArt(a.id)) continue
                val cover = runCatching { deezerCover(a.artistName, a.title) }.getOrNull() ?: continue
                runCatching {
                    val resp = Http.get(cover, timeoutMs = 15_000)
                    if (resp.ok && resp.bytes.size > 1_000) { cache.writeBytes(resp.bytes); fetched++ }
                }
                delay(250) // be polite to Deezer
            }
            log.info("Enrichment done: fetched {} covers", fetched)
        } finally {
            running = false
            mutex.unlock()
        }
    }

    private fun deezerCover(artist: String, album: String): String? {
        if (album.isBlank() || album.equals("Unknown Album", ignoreCase = true)) return null
        val q = URLEncoder.encode("$artist $album".trim(), "UTF-8")
        val resp = Http.get("https://api.deezer.com/search/album?q=$q&limit=1")
        if (!resp.ok) return null
        val parsed = runCatching { Http.json.decodeFromString<DeezerAlbumSearch>(resp.body) }.getOrNull() ?: return null
        return parsed.data.firstOrNull()?.let { it.coverXl ?: it.coverBig }?.takeIf { it.isNotBlank() }
    }
}
