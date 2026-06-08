package com.debridmusic.app.data.remote.dto

import com.google.gson.annotations.SerializedName

// ── Generic wrapper ──────────────────────────────────────────────────────────

data class TorBoxResponse<T>(
    val success: Boolean = false,
    val error: String? = null,
    val detail: String? = null,
    val data: T? = null,
)

// ── Search ───────────────────────────────────────────────────────────────────

data class TorBoxSearchResult(
    @SerializedName("raw_title") val rawTitle: String = "",
    val name: String = "",
    val size: Long = 0L,
    val seeders: Int = 0,
    val leechers: Int = 0,
    val magnet: String = "",
    val hash: String = "",
    val score: Float = 0f,
    val sources: List<String>? = null,
    val category: String? = null,
    val imdbId: String? = null,
    val source: String? = null,
)

// ── Create torrent ───────────────────────────────────────────────────────────

data class TorBoxCreateData(
    @SerializedName("torrent_id") val torrentId: Long = 0,
    val name: String? = null,
    val hash: String? = null,
    val detail: String? = null,
)

// ── Torrent list ─────────────────────────────────────────────────────────────

data class TorBoxTorrentItem(
    val id: Long = 0,
    val name: String = "",
    val hash: String? = null,
    val status: String = "",
    val progress: Float = 0f,
    val size: Long = 0L,
    @SerializedName("download_speed") val downloadSpeed: Long = 0L,
    @SerializedName("time_seeding") val timeSeeding: Int = 0,
    val files: List<TorBoxFile>? = null,
    val ratio: Float = 0f,
    @SerializedName("created_at") val createdAt: String? = null,
    @SerializedName("updated_at") val updatedAt: String? = null,
    @SerializedName("download_present") val downloadPresent: Boolean = false,
    @SerializedName("download_finished") val downloadFinished: Boolean = false,
    val cached: Boolean = false,
) {
    val isReady get() = status == "completed" || cached || downloadFinished
    val isActive get() = status == "downloading" || status == "processing" || status == "queued"
    val isFailed get() = status == "error" || status == "stalled"
}

data class TorBoxFile(
    val id: Long = 0,
    val name: String = "",
    @SerializedName("short_name") val shortName: String? = null,
    val size: Long = 0L,
    @SerializedName("s3_path") val s3Path: String? = null,
    @SerializedName("mime_type") val mimeType: String? = null,
) {
    val isAudio: Boolean get() {
        val mime = mimeType?.lowercase() ?: ""
        val ext = name.substringAfterLast('.').lowercase()
        return mime.startsWith("audio/") ||
                ext in setOf("flac", "mp3", "m4a", "aac", "ogg", "opus", "wav", "alac", "ape", "wv")
    }
    val isFlac: Boolean get() =
        mimeType?.contains("flac") == true || name.endsWith(".flac", ignoreCase = true)
}

// ── Download link ─────────────────────────────────────────────────────────────

// data field is a plain string URL

// ── BitSearch (external torrent search) ──────────────────────────────────────

data class BitSearchResponse(
    val success: Boolean = false,
    val query: String? = null,
    val results: List<BitSearchResult>? = null,
)

data class BitSearchResult(
    val infohash: String = "",
    val title: String = "",
    val size: Long = 0L,
    val seeders: Int = 0,
    val leechers: Int = 0,
    val verified: Boolean = false,
)

// ── User ──────────────────────────────────────────────────────────────────────

data class TorBoxUser(
    val id: Long = 0,
    val email: String? = null,
    val plan: Int = 0,
    @SerializedName("premium_expires_at") val premiumExpiresAt: String? = null,
    @SerializedName("is_subscribed") val isSubscribed: Boolean = false,
    @SerializedName("total_downloaded") val totalDownloaded: Long = 0L,
    @SerializedName("customer") val customer: String? = null,
)
