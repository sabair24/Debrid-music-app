package com.debridmusic.app.download

import android.content.Context
import android.net.Uri
import android.os.Environment
import androidx.documentfile.provider.DocumentFile
import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.local.dao.AlbumDao
import com.debridmusic.app.data.local.dao.ArtistDao
import com.debridmusic.app.data.local.dao.DownloadDao
import com.debridmusic.app.data.local.dao.TrackDao
import com.debridmusic.app.data.local.entity.AlbumEntity
import com.debridmusic.app.data.local.entity.ArtistEntity
import com.debridmusic.app.data.local.entity.DownloadEntity
import com.debridmusic.app.data.local.entity.DownloadStatus
import com.debridmusic.app.data.local.entity.TrackEntity
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.OutputStream
import javax.inject.Inject
import javax.inject.Singleton

/** A track to enqueue for offline download. */
data class DownloadRequest(
    val title: String,
    val artist: String,
    val album: String,
    val sourceUrl: String,
    val artworkUri: String? = null,
    val addToLibrary: Boolean = false,
)

@Singleton
class OfflineDownloadManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val downloadDao: DownloadDao,
    private val artistDao: ArtistDao,
    private val albumDao: AlbumDao,
    private val trackDao: TrackDao,
    private val okHttpClient: OkHttpClient,
    private val settingsStore: SettingsStore,
    private val appScope: CoroutineScope,
) {
    fun observeAll() = downloadDao.observeAll()

    // Up to the user's configured limit run at once; the rest wait in the queue.
    private val drainMutex = Mutex()   // only one drainer coroutine at a time
    private val claimMutex = Mutex()   // atomically claim the next queued row

    /** Queue one track. Returns immediately; the worker processes downloads serially. */
    fun enqueue(request: DownloadRequest) = enqueueAll(listOf(request))

    /** Queue many tracks (e.g. a full album); they download one after another. */
    fun enqueueAll(requests: List<DownloadRequest>) {
        if (requests.isEmpty()) return
        appScope.launch {
            requests.forEach { r ->
                downloadDao.insert(
                    DownloadEntity(
                        title = r.title, artist = r.artist, album = r.album,
                        sourceUrl = r.sourceUrl, artworkUri = r.artworkUri,
                        status = DownloadStatus.QUEUED.name, addToLibrary = r.addToLibrary,
                    )
                )
            }
            processQueue()
        }
    }

    /** Drains QUEUED downloads with up to the configured number running in parallel. */
    private suspend fun processQueue() {
        if (!drainMutex.tryLock()) return // a drain is already in progress
        try {
            val slots = Semaphore(settingsStore.maxConcurrentDownloads.first())
            do {
                coroutineScope {
                    val jobs = mutableListOf<Job>()
                    while (true) {
                        slots.acquire()
                        val next = claimNext()
                        if (next == null) { slots.release(); break }
                        jobs += launch {
                            try { downloadOne(next) } finally { slots.release() }
                        }
                    }
                    jobs.joinAll()
                }
                // Re-check in case tracks were queued while we were draining.
            } while (downloadDao.nextQueued() != null)
            enforceQuota()
        } finally {
            drainMutex.unlock()
        }
    }

    /** Atomically pull the next QUEUED row and mark it DOWNLOADING so no two workers grab it. */
    private suspend fun claimNext(): DownloadEntity? = claimMutex.withLock {
        val next = downloadDao.nextQueued() ?: return@withLock null
        val claimed = next.copy(status = DownloadStatus.DOWNLOADING.name)
        downloadDao.update(claimed)
        claimed
    }

    private suspend fun downloadOne(entity: DownloadEntity) {
        val id = entity.id
        val ext = if (entity.sourceUrl.contains("flac", ignoreCase = true)) "flac" else "mp3"
        val safeName = "${entity.title}_${entity.artist}".replace(Regex("[^a-zA-Z0-9._-]"), "_")
        val dest = resolveDestination("$safeName.$ext", ext)
        try {
            // status already set to DOWNLOADING by claimNext()
            val response = okHttpClient.newCall(Request.Builder().url(entity.sourceUrl).build()).execute()
            val body = response.body ?: error("Empty response body")
            val totalBytes = body.contentLength().coerceAtLeast(0L)
            var downloadedBytes = 0L
            var lastUpdateBytes = 0L
            body.byteStream().use { input ->
                dest.openOutput().buffered(BUFFER_SIZE).use { output ->
                    val buffer = ByteArray(BUFFER_SIZE)
                    var n: Int
                    while (input.read(buffer).also { n = it } != -1) {
                        output.write(buffer, 0, n)
                        downloadedBytes += n
                        if (downloadedBytes - lastUpdateBytes > 2_000_000L) {
                            lastUpdateBytes = downloadedBytes
                            downloadDao.getById(id)?.let {
                                downloadDao.update(it.copy(downloadedBytes = downloadedBytes, sizeBytes = totalBytes, localPath = dest.localPath))
                            }
                        }
                    }
                }
            }
            downloadDao.getById(id)?.let {
                val done = it.copy(
                    status = DownloadStatus.DONE.name,
                    downloadedBytes = downloadedBytes,
                    sizeBytes = if (totalBytes > 0) totalBytes else downloadedBytes,
                    localPath = dest.localPath,
                )
                downloadDao.update(done)
                if (done.addToLibrary) addDownloadToLibrary(done)
            }
        } catch (e: Exception) {
            dest.delete()
            downloadDao.getById(id)?.let { downloadDao.update(it.copy(status = DownloadStatus.FAILED.name)) }
        }
    }

    /** Inserts a finished download into the library as a local track (artist/album upserted). */
    private suspend fun addDownloadToLibrary(d: DownloadEntity) {
        runCatching {
            val artistId = artistDao.getByName(d.artist)?.id
                ?: artistDao.insert(ArtistEntity(name = d.artist, imageUri = d.artworkUri))
            val albumId = albumDao.getByTitleAndArtist(d.album, artistId)?.id
                ?: albumDao.insert(AlbumEntity(title = d.album, artistId = artistId, artistName = d.artist, artworkUri = d.artworkUri))
            trackDao.insert(
                TrackEntity(
                    title = d.title, artistName = d.artist, albumTitle = d.album,
                    albumId = albumId, artistId = artistId, uri = d.localPath, durationMs = 0L,
                    artworkUri = d.artworkUri, isLossless = d.localPath.endsWith(".flac", ignoreCase = true),
                    fileSize = d.sizeBytes, sourceType = "local",
                ),
            )
        }
    }

    suspend fun deleteDownload(id: Long) {
        val entity = downloadDao.getById(id) ?: return
        deleteLocal(entity.localPath)
        downloadDao.deleteById(id)
    }

    // ── Storage management ──────────────────────────────────────────────────────
    suspend fun downloadsSizeBytes(): Long = downloadDao.completedSizeBytes()

    fun cacheSizeBytes(): Long = context.cacheDir.walkBottomUp().filter { it.isFile }.sumOf { it.length() }

    fun clearCache() {
        runCatching { context.cacheDir.listFiles()?.forEach { it.deleteRecursively() } }
    }

    suspend fun clearAllDownloads() {
        downloadDao.getCompleted().forEach { deleteLocal(it.localPath); downloadDao.deleteById(it.id) }
    }

    suspend fun enforceQuota() {
        val max = settingsStore.maxDownloadBytes.first()
        if (max <= 0L) return
        var total = downloadDao.completedSizeBytes()
        if (total <= max) return
        for (d in downloadDao.getCompletedOldestFirst()) {
            if (total <= max) break
            deleteLocal(d.localPath)
            downloadDao.deleteById(d.id)
            total -= d.sizeBytes
        }
    }

    // ── Destination resolution (SAF tree URI or app external dir) ────────────────
    private class Destination(val localPath: String, val openOutput: () -> OutputStream, val delete: () -> Unit)

    private suspend fun resolveDestination(fileName: String, ext: String): Destination {
        val treeUriStr = settingsStore.downloadTreeUri.first()
        if (treeUriStr.isNotBlank()) {
            val tree = DocumentFile.fromTreeUri(context, Uri.parse(treeUriStr))
            val mime = if (ext == "flac") "audio/flac" else "audio/mpeg"
            val doc = tree?.createFile(mime, fileName)
            if (doc != null) {
                val uri = doc.uri
                return Destination(
                    localPath = uri.toString(),
                    openOutput = { context.contentResolver.openOutputStream(uri) ?: error("Kan niet schrijven naar map") },
                    delete = { runCatching { DocumentFile.fromSingleUri(context, uri)?.delete() } },
                )
            }
        }
        val dir = context.getExternalFilesDir(Environment.DIRECTORY_MUSIC) ?: context.filesDir
        val file = File(dir, fileName)
        return Destination(
            localPath = file.absolutePath,
            openOutput = { file.outputStream() },
            delete = { runCatching { file.delete() } },
        )
    }

    private fun deleteLocal(localPath: String) {
        if (localPath.isBlank()) return
        if (localPath.startsWith("content://")) {
            runCatching { DocumentFile.fromSingleUri(context, Uri.parse(localPath))?.delete() }
        } else {
            runCatching { File(localPath).delete() }
        }
    }

    private companion object {
        const val BUFFER_SIZE = 262_144     // 256 KB read/write buffer
    }
}
