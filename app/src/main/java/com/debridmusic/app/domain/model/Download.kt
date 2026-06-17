package com.debridmusic.app.domain.model

import com.debridmusic.app.data.local.entity.DownloadStatus

data class Download(
    val id: Long,
    val title: String,
    val artist: String,
    val album: String,
    val sourceUrl: String,
    val localPath: String,
    val sizeBytes: Long,
    val downloadedBytes: Long,
    val status: DownloadStatus,
    val dateAdded: Long,
    val artworkUri: String? = null,
) {
    val progress: Float get() = if (sizeBytes > 0) downloadedBytes.toFloat() / sizeBytes else 0f
    val isComplete: Boolean get() = status == DownloadStatus.DONE
    val isActive: Boolean get() = status == DownloadStatus.DOWNLOADING || status == DownloadStatus.QUEUED
}
