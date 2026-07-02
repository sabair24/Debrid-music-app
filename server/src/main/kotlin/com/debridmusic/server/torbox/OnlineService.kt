package com.debridmusic.server.torbox

import com.debridmusic.server.ServerSettings
import com.debridmusic.server.search.SearchAggregator
import com.debridmusic.server.search.SearchResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import org.slf4j.LoggerFactory
import java.io.File
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicLong

// ── Wire DTOs (web UI) ───────────────────────────────────────────────────────
@Serializable
data class OnlineFileDto(val id: Long, val name: String, val size: Long, val flac: Boolean)

@Serializable
data class TrackListDto(val torrentId: Long, val torrentName: String, val files: List<OnlineFileDto>)

@Serializable
data class ResolvedDto(val url: String, val name: String)

@Serializable
data class DownloadJobDto(val id: Long, val name: String, val torrent: String, val status: String, val progress: Float)

@Serializable
data class OnlineDownloadRequest(val result: SearchResult, val fileId: Long? = null)

/**
 * Orchestrates the "find online → stream/download" pipeline on the server:
 * aggregated search (with TorBox instant-cache ranking), resolve a torrent to a
 * playable URL, list its tracks, and download tracks into the music library.
 */
class OnlineService(
    private val settings: ServerSettings,
    private val aggregator: SearchAggregator,
    private val client: TorBoxClient,
    private val musicRoot: File,
    private val onLibraryChanged: () -> Unit,
    private val appScope: CoroutineScope,
) {
    private val log = LoggerFactory.getLogger(OnlineService::class.java)
    private val ids = AtomicLong(1)
    private val jobs = CopyOnWriteArrayList<Job>()

    private class Job(val id: Long, val name: String, val torrent: String) {
        @Volatile var status = "downloading"
        @Volatile var progress = 0f
    }

    private val http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(20))
        .followRedirects(HttpClient.Redirect.NORMAL).build()

    fun torBoxReady() = client.hasKey()

    // ── search ────────────────────────────────────────────────────────────────
    suspend fun search(query: String): List<SearchResult> {
        val results = aggregator.search(query)
        if (!client.hasKey()) return results
        val cached = runCatching { markCached(results) }.getOrDefault(emptySet())
        return results.map { it.copy(cached = it.hash.lowercase() in cached) }
            .sortedWith(compareByDescending<SearchResult> { it.cached }.thenByDescending { it.seeders })
    }

    private suspend fun markCached(results: List<SearchResult>): Set<String> {
        val top = results.take(CACHED_CHECK_LIMIT).map { it.hash.lowercase() }
        val out = HashSet<String>()
        top.chunked(CACHED_CHECK_BATCH).forEach { batch -> out += client.checkCached(batch) }
        return out
    }

    // ── resolve / stream ────────────────────────────────────────────────────────
    private data class TorrentRef(val id: Long?, val hash: String)

    private suspend fun addOrFindTorrent(result: SearchResult): TorrentRef {
        val create = client.addMagnet(result.magnet)
        val hash = create.data?.hash?.takeIf { it.isNotBlank() } ?: result.hash
        require(hash.isNotBlank()) { "Torrent has no infohash" }
        if (create.success) return TorrentRef(create.data?.torrentId?.takeIf { it > 0 }, hash)
        val detail = (create.detail ?: create.error).orEmpty()
        if (detail.contains("already", ignoreCase = true)) {
            val item = client.listTorrents().firstOrNull { it.hash.equals(hash, ignoreCase = true) }
            return TorrentRef(item?.id, hash)
        }
        error(create.detail ?: create.error ?: "Failed to add torrent")
    }

    private suspend fun pollUntilReady(ref: TorrentRef, patient: Boolean): TbTorrent {
        var delayMs = 2000L
        var noProgressMs = 0L
        var readyNoAudioMs = 0L
        val maxAttempts = if (patient) 45 else 30
        val stallTimeout = if (patient) 45_000L else 25_000L
        repeat(maxAttempts) { attempt ->
            val item = client.listTorrents().firstOrNull {
                (ref.id != null && it.id == ref.id) || it.hash.equals(ref.hash, ignoreCase = true)
            }
            when {
                item == null -> noProgressMs += delayMs
                item.isFailed -> error("Torrent failed: ${item.status}")
                item.isReady && item.files.orEmpty().any { it.isAudio } -> return item
                item.isReady -> {
                    readyNoAudioMs += delayMs
                    if (readyNoAudioMs >= READY_NO_AUDIO_TIMEOUT_MS)
                        error("Geen afspeelbare audio in deze bron (bijv. DSD/SACD)")
                }
                else -> if (item.progress <= 0f) noProgressMs += delayMs else noProgressMs = 0
            }
            if (noProgressMs >= stallTimeout) error("Source stalled — no progress")
            delay(delayMs)
            if (attempt >= 1) delayMs = (delayMs * 1.5).toLong().coerceAtMost(10_000)
        }
        error("Timed out preparing this source")
    }

    private fun bestAudio(item: TbTorrent): TbFile? =
        item.files.orEmpty().filter { it.isAudio }
            .sortedWith(compareByDescending<TbFile> { if (it.isFlac) 1 else 0 }.thenByDescending { it.size })
            .firstOrNull()

    private fun sortedAudio(item: TbTorrent): List<TbFile> =
        item.files.orEmpty().filter { it.isAudio }
            .sortedWith(compareByDescending<TbFile> { if (it.isFlac) 1 else 0 }.thenBy { it.name })

    /** Resolve the single best track of a result to a playable URL. */
    suspend fun resolveStreamUrl(result: SearchResult): String {
        require(client.hasKey()) { "Stel eerst je TorBox API-sleutel in (Instellingen)." }
        val item = pollUntilReady(addOrFindTorrent(result), patient = !result.cached)
        val best = bestAudio(item) ?: error("No audio files found in this torrent")
        return client.requestDownload(item.id, best.id) ?: error("Empty download URL")
    }

    /** List the audio tracks of a result (for the track picker). */
    suspend fun tracklist(result: SearchResult): TrackListDto {
        require(client.hasKey()) { "Stel eerst je TorBox API-sleutel in (Instellingen)." }
        val item = pollUntilReady(addOrFindTorrent(result), patient = false)
        val files = sortedAudio(item).map { OnlineFileDto(it.id, it.shortName ?: it.name, it.size, it.isFlac) }
        if (files.isEmpty()) error("No audio files found in this torrent")
        return TrackListDto(item.id, item.name, files)
    }

    suspend fun resolveTrackUrl(torrentId: Long, fileId: Long): String =
        client.requestDownload(torrentId, fileId) ?: error("Empty download URL")

    // ── download to library ──────────────────────────────────────────────────────
    fun jobs(): List<DownloadJobDto> = jobs.map { DownloadJobDto(it.id, it.name, it.torrent, it.status, it.progress) }

    /** Queue a download of one file (fileId!=null) or every audio track of a result. Returns file count. */
    suspend fun enqueueDownload(result: SearchResult, fileId: Long?): Int {
        require(client.hasKey()) { "Stel eerst je TorBox API-sleutel in (Instellingen)." }
        val item = pollUntilReady(addOrFindTorrent(result), patient = !result.cached)
        val chosen = if (fileId != null) item.files.orEmpty().filter { it.id == fileId } else sortedAudio(item)
        if (chosen.isEmpty()) error("No audio files found")
        val destDir = File(musicRoot, "DebridMusic Downloads/${sanitize(item.name)}").apply { mkdirs() }
        chosen.forEach { file ->
            val job = Job(ids.getAndIncrement(), file.shortName ?: file.name, item.name)
            jobs.add(0, job)
            appScope.launch(Dispatchers.IO) { downloadOne(item.id, file, destDir, job) }
        }
        return chosen.size
    }

    private suspend fun downloadOne(torrentId: Long, file: TbFile, destDir: File, job: Job) {
        try {
            val url = client.requestDownload(torrentId, file.id) ?: error("no url")
            val name = sanitize(file.shortName ?: file.name)
            val dest = File(destDir, name)
            val req = HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofMinutes(30)).GET().build()
            val resp = http.send(req, HttpResponse.BodyHandlers.ofInputStream())
            if (resp.statusCode() !in 200..299) error("HTTP ${resp.statusCode()}")
            val total = resp.headers().firstValueAsLong("content-length").orElse(file.size).coerceAtLeast(1)
            var done = 0L
            resp.body().use { input ->
                dest.outputStream().use { out ->
                    val buf = ByteArray(1 shl 16)
                    while (true) {
                        val n = input.read(buf); if (n < 0) break
                        out.write(buf, 0, n); done += n
                        job.progress = (done.toFloat() / total).coerceIn(0f, 1f)
                    }
                }
            }
            job.progress = 1f; job.status = "done"
            log.info("Downloaded {} -> {}", file.name, dest.absolutePath)
            onLibraryChanged()
        } catch (e: Exception) {
            job.status = "failed"
            log.warn("Download failed for {}: {}", file.name, e.message)
        }
    }

    private fun sanitize(s: String) = s.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim().ifEmpty { "track" }

    companion object {
        const val CACHED_CHECK_LIMIT = 40
        const val CACHED_CHECK_BATCH = 20
        const val READY_NO_AUDIO_TIMEOUT_MS = 18_000L
    }
}
