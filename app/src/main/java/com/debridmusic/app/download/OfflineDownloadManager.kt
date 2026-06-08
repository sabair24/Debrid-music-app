package com.debridmusic.app.download

import android.content.Context
import android.os.Environment
import com.debridmusic.app.data.local.dao.DownloadDao
import com.debridmusic.app.data.local.entity.DownloadEntity
import com.debridmusic.app.data.local.entity.DownloadStatus
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class OfflineDownloadManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val downloadDao: DownloadDao,
    private val okHttpClient: OkHttpClient,
) {
    fun observeAll() = downloadDao.observeAll()

    fun startDownload(
        title: String,
        artist: String,
        album: String,
        sourceUrl: String,
    ): Flow<DownloadStatus> = flow {
        val entity = DownloadEntity(
            title = title, artist = artist, album = album, sourceUrl = sourceUrl,
        )
        val id = downloadDao.insert(entity)
        emit(DownloadStatus.QUEUED)

        val dir = context.getExternalFilesDir(Environment.DIRECTORY_MUSIC) ?: context.filesDir
        val safeName = "${title}_${artist}".replace(Regex("[^a-zA-Z0-9._-]"), "_")
        val ext = if (sourceUrl.contains("flac", ignoreCase = true)) "flac" else "mp3"
        val file = File(dir, "$safeName.$ext")

        try {
            downloadDao.update(
                downloadDao.getById(id)!!.copy(status = DownloadStatus.DOWNLOADING.name)
            )
            emit(DownloadStatus.DOWNLOADING)

            val request = Request.Builder().url(sourceUrl).build()
            val response = okHttpClient.newCall(request).execute()
            val body = response.body ?: error("Empty response body")

            val totalBytes = body.contentLength().coerceAtLeast(0L)
            var downloadedBytes = 0L
            var lastUpdateBytes = 0L

            body.byteStream().use { input ->
                file.outputStream().use { output ->
                    val buffer = ByteArray(65_536)
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        downloadedBytes += bytesRead
                        if (downloadedBytes - lastUpdateBytes > 512_000L) {
                            lastUpdateBytes = downloadedBytes
                            downloadDao.update(
                                downloadDao.getById(id)!!.copy(
                                    downloadedBytes = downloadedBytes,
                                    sizeBytes = totalBytes,
                                    localPath = file.absolutePath,
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
                    localPath = file.absolutePath,
                )
            )
            emit(DownloadStatus.DONE)
        } catch (e: Exception) {
            file.delete()
            downloadDao.getById(id)?.let {
                downloadDao.update(it.copy(status = DownloadStatus.FAILED.name))
            }
            emit(DownloadStatus.FAILED)
        }
    }.flowOn(Dispatchers.IO)

    suspend fun deleteDownload(id: Long) {
        val entity = downloadDao.getById(id) ?: return
        if (entity.localPath.isNotBlank()) File(entity.localPath).delete()
        downloadDao.deleteById(id)
    }
}
