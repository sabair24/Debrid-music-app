package com.debridmusic.app.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

enum class DownloadStatus { QUEUED, DOWNLOADING, DONE, FAILED, CANCELLED }

@Entity(tableName = "downloads")
data class DownloadEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val title: String,
    val artist: String,
    val album: String,
    val sourceUrl: String,
    val localPath: String = "",
    val sizeBytes: Long = 0L,
    val downloadedBytes: Long = 0L,
    val status: String = DownloadStatus.QUEUED.name,
    val dateAdded: Long = System.currentTimeMillis(),
    val artworkUri: String? = null,
    // When true, the finished file is also inserted into the library as a local track.
    val addToLibrary: Boolean = false,
)
