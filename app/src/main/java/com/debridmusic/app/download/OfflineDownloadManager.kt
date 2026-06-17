package com.debridmusic.app.download

import android.content.Context
import android.net.Uri
import android.os.Environment
import androidx.documentfile.provider.DocumentFile
import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.local.dao.DownloadDao
import com.debridmusic.app.data.local.entity.DownloadEntity
import com.debridmusic.app.data.local.entity.DownloadStatus
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.OutputStream
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class OfflineDownloadManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val downloadDao: DownloadDao,
    private val okHttpClient: OkHttpClient,
    private val settingsStore: SettingsStore,
) {
    fun observeAll() = downloadDao.observeAll()

    fun startDownload(
        title: String,
        artist: String,
        album: String,
        sourceUrl: String,
        artworkUri: String? = null,
    ): Flow<DownloadStatus> = flow {
        val id = downloadDao.insert(
            DownloadEntity(title = title, artist = artist, album = album, sourceUrl = sourceUrl, artworkUri = artworkUri)
        )
        emit(DownloadStatus.QUEUED)

        val ext = if (sourceUrl.contains("flac", ignoreCase = true)) "flac" else "mp3"
        val safeName = "${title}_${artist}".replace(Regex("[^a-zA-Z0-9._-]"), "_")
        val fileName = "$safeName.$ext"
        val dest = resolveDestination(fileName, ext)

        try {
            downloadDao.update(downloadDao.getById(id)!!.copy(status = DownloadStatus.DOWNLOADING.name))
            emit(DownloadStatus.DOWNLOADING)

            val response = okHttpClient.newCall(Request.Builder().url(sourceUrl).build()).execute()
            val body = response.body ?: error("Empty response body")
            val totalBytes = body.contentLength().coerceAtLeast(0L)
            var downloadedBytes = 0L
            var lastUpdateBytes = 0L

            body.byteStream().use { input ->
                dest.openOutput().use { output ->
                    val buffer = ByteArray(65_536)
                    var n: Int
                    while (input.read(buffer).also { n = it } != -1) {
                        output.write(buffer, 0, n)
                        downloadedBytes += n
                        if (downloadedBytes - lastUpdateBytes > 512_000L) {
                            lastUpdateBytes = downloadedBytes
                            downloadDao.update(
                                downloadDao.getById(id)!!.copy(
                                    downloadedBytes = downloadedBytes, sizeBytes = totalBytes, localPath = dest.localPath,
                                )
                            )
                        }
                    }
                }
            }

            downloadDao.update(
                downloadDao.getById(id)!!.copy(
                    status = DownloadStatus.DONE.name,
                    downloadedBytes = downloadedBytes,
                    sizeBytes = if (totalBytes > 0) totalBytes else downloadedBytes,
                    localPath = dest.localPath,
                )
            )
            emit(DownloadStatus.DONE)
            enforceQuota()
        } catch (e: Exception) {
            dest.delete()
            downloadDao.getById(id)?.let { downloadDao.update(it.copy(status = DownloadStatus.FAILED.name)) }
            emit(DownloadStatus.FAILED)
        }
    }.flowOn(Dispatchers.IO)

    suspend fun deleteDownload(id: Long) {
        val entity = downloadDao.getById(id) ?: return
        deleteLocal(entity.localPath)
        downloadDao.deleteById(id)
    }

    // ── Storage management ──────────────────────────────────────────────────────
    suspend fun downloadsSizeBytes(): Long = downloadDao.completedSizeBytes()

    /** Total bytes in the app cache dir (Soulseek temp files, update APK, etc.). */
    fun cacheSizeBytes(): Long = context.cacheDir.walkBottomUp().filter { it.isFile }.sumOf { it.length() }

    fun clearCache() {
        runCatching { context.cacheDir.listFiles()?.forEach { it.deleteRecursively() } }
    }

    suspend fun clearAllDownloads() {
        downloadDao.getCompleted().forEach { deleteLocal(it.localPath); downloadDao.deleteById(it.id) }
    }

    /** Deletes oldest completed downloads until under the configured size cap. */
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
}
