package com.debridmusic.server.metadata

import com.debridmusic.server.ServerSettings
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

@Serializable private data class DeezerAlbumSearch(val data: List<DeezerAlbum> = emptyList())
@Serializable private data class DeezerAlbum(@SerialName("cover_big") val coverBig: String? = null, @SerialName("cover_xl") val coverXl: String? = null)
@Serializable private data class DiscogsSearch(val results: List<DiscogsResult> = emptyList())
@Serializable private data class DiscogsResult(@SerialName("cover_image") val coverImage: String? = null, val thumb: String? = null)
@Serializable private data class MbSearch(val releases: List<MbRelease> = emptyList())
@Serializable private data class MbRelease(val id: String = "")

/**
 * Fills missing album cover art from Deezer → Discogs → MusicBrainz/CoverArtArchive,
 * caching it as `<artCacheDir>/<albumId>.jpg` (served by [ArtworkService] as a fallback).
 * Idempotent + safe to re-run; auto-runs on startup and after each library change.
 */
class EnrichmentService(
    private val store: IndexStore,
    private val artwork: ArtworkService,
    private val artCacheDir: File,
    private val appScope: CoroutineScope,
    private val settings: ServerSettings,
) {
    private val log = LoggerFactory.getLogger(EnrichmentService::class.java)
    private val mutex = Mutex()
    private val UA_APP = "DebridMusic/0.1 ( https://github.com/sabair24/Debrid-music-app )"
    private val GENERIC_ARTISTS = setOf("various", "various artists", "va", "unknown artist", "unknown", "")

    @Volatile private var running = false
    @Volatile private var done = 0
    @Volatile private var total = 0
    @Volatile private var fetched = 0
    @Volatile private var pending = false
    @Volatile private var srcDeezer = 0
    @Volatile private var srcDiscogs = 0
    @Volatile private var srcMb = 0

    fun status() = EnrichStatusDto(running, done, total, fetched)

    fun enrichInBackground() {
        appScope.launch { runCatching { enrichAll() }.onFailure { log.warn("enrich failed: {}", it.message) } }
    }

    suspend fun enrichAll() {
        if (!mutex.tryLock()) { pending = true; return }
        try {
            running = true
            do {
                pending = false
                done = 0; fetched = 0; srcDeezer = 0; srcDiscogs = 0; srcMb = 0
                artCacheDir.mkdirs()
                val albums = store.albums()
                total = albums.size
                log.info("Enrichment: scanning {} albums for missing art…", total)
                for (a in albums) {
                    done++
                    val cache = File(artCacheDir, "${a.id}.jpg")
                    if (cache.isFile || artwork.hasLocalArt(a.id)) continue
                    val bytes = runCatching { findCover(a.artistName, a.title) }.getOrNull()
                    if (bytes != null) { cache.writeBytes(bytes); fetched++ }
                    delay(200)
                }
                log.info("Enrichment pass done: fetched {} covers (deezer={}, discogs={}, musicbrainz={})", fetched, srcDeezer, srcDiscogs, srcMb)
            } while (pending)
        } finally {
            running = false
            mutex.unlock()
        }
    }

    /** Try each source in turn; return the first real image's bytes. */
    private suspend fun findCover(artist: String, album: String): ByteArray? {
        if (album.isBlank() || album.equals("Unknown Album", ignoreCase = true)) return null
        val generic = artist.trim().lowercase() in GENERIC_ARTISTS
        val query = if (generic) album else "$artist $album"

        deezerCover(query)?.let { url -> downloadImage(url)?.let { srcDeezer++; return it } }

        settings.get(ServerSettings.DISCOGS_TOKEN)?.let { token ->
            discogsCover(if (generic) album else artist, album, generic, token)?.let { url ->
                downloadImage(url)?.let { srcDiscogs++; return it }
            }
        }

        musicbrainzCover(if (generic) "" else artist, album)?.let { srcMb++; return it }
        return null
    }

    private fun deezerCover(query: String): String? {
        val resp = Http.get("https://api.deezer.com/search/album?q=${enc(query)}&limit=1")
        if (!resp.ok) return null
        val parsed = runCatching { Http.json.decodeFromString<DeezerAlbumSearch>(resp.body) }.getOrNull() ?: return null
        return parsed.data.firstOrNull()?.let { it.coverXl ?: it.coverBig }?.takeIf { it.isNotBlank() }
    }

    private fun discogsCover(artist: String, album: String, generic: Boolean, token: String): String? {
        val url = buildString {
            append("https://api.discogs.com/database/search?type=release&token=").append(enc(token))
            append("&release_title=").append(enc(album))
            if (!generic && artist.isNotBlank()) append("&artist=").append(enc(artist))
        }
        val resp = Http.get(url, mapOf("User-Agent" to UA_APP))
        if (!resp.ok) return null
        val parsed = runCatching { Http.json.decodeFromString<DiscogsSearch>(resp.body) }.getOrNull() ?: return null
        return parsed.results.asSequence()
            .mapNotNull { it.coverImage ?: it.thumb }
            .firstOrNull { it.isNotBlank() && !it.contains("spacer.gif") }
    }

    /** MusicBrainz release search → CoverArtArchive front image bytes. Rate-limited. */
    private suspend fun musicbrainzCover(artist: String, album: String): ByteArray? {
        val q = buildString {
            append("release:\"").append(album).append("\"")
            if (artist.isNotBlank()) append(" AND artist:\"").append(artist).append("\"")
        }
        delay(1100) // MusicBrainz asks for ≤1 request/second
        val resp = Http.get("https://musicbrainz.org/ws/2/release/?query=${enc(q)}&fmt=json&limit=3", mapOf("User-Agent" to UA_APP))
        if (!resp.ok) return null
        val parsed = runCatching { Http.json.decodeFromString<MbSearch>(resp.body) }.getOrNull() ?: return null
        for (rel in parsed.releases.take(3)) {
            if (rel.id.isBlank()) continue
            downloadImage("https://coverartarchive.org/release/${rel.id}/front-500")?.let { return it }
        }
        return null
    }

    private fun downloadImage(url: String): ByteArray? {
        val resp = runCatching { Http.get(url, timeoutMs = 15_000) }.getOrNull() ?: return null
        return if (resp.ok && resp.bytes.size > 1_500 && isImage(resp.bytes)) resp.bytes else null
    }

    private fun isImage(b: ByteArray): Boolean {
        if (b.size < 12) return false
        val jpg = b[0] == 0xFF.toByte() && b[1] == 0xD8.toByte()
        val png = b[0] == 0x89.toByte() && b[1] == 0x50.toByte() && b[2] == 0x4E.toByte() && b[3] == 0x47.toByte()
        val gif = b[0] == 'G'.code.toByte() && b[1] == 'I'.code.toByte() && b[2] == 'F'.code.toByte()
        val webp = b[0] == 'R'.code.toByte() && b[1] == 'I'.code.toByte() && b[8] == 'W'.code.toByte() && b[9] == 'E'.code.toByte()
        return jpg || png || gif || webp
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
}
