package com.debridmusic.app.domain.model

data class Track(
    val id: Long,
    val title: String,
    val artistName: String,
    val albumTitle: String,
    val albumId: Long,
    val artistId: Long,
    val uri: String,
    val durationMs: Long,
    val trackNumber: Int,
    val discNumber: Int,
    val year: Int?,
    val artworkUri: String?,
    val genre: String?,
    val bitrate: Int?,
    val sampleRate: Int?,
    val isLossless: Boolean,
    val fileSize: Long,
    val dateAdded: Long,
    val sourceType: String = "local",
    val torrentHash: String? = null,
    val torrentFileName: String? = null,
    val serverTrackId: String? = null,
) {
    val isOnline: Boolean get() = sourceType == "online"
    val isServer: Boolean get() = sourceType == "server"

    val formattedDuration: String get() {
        val totalSeconds = durationMs / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return "%d:%02d".format(minutes, seconds)
    }
}
