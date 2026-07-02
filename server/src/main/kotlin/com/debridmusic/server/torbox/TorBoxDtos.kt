package com.debridmusic.server.torbox

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class TbFile(
    val id: Long = 0,
    val name: String = "",
    @SerialName("short_name") val shortName: String? = null,
    val size: Long = 0,
    @SerialName("mime_type") val mimeType: String? = null,
) {
    private val ext get() = name.substringAfterLast('.', "").lowercase()
    val isAudio: Boolean get() = mimeType?.startsWith("audio/") == true || ext in AUDIO_EXTS
    val isFlac: Boolean get() = mimeType?.contains("flac") == true || name.endsWith(".flac", ignoreCase = true)

    companion object {
        val AUDIO_EXTS = setOf("flac", "mp3", "m4a", "aac", "ogg", "opus", "wav", "alac", "ape", "wv")
    }
}

@Serializable
data class TbTorrent(
    val id: Long = 0,
    val name: String = "",
    val hash: String? = null,
    val status: String = "",
    val progress: Float = 0f,
    val size: Long = 0,
    val files: List<TbFile>? = null,
    @SerialName("download_finished") val downloadFinished: Boolean = false,
    val cached: Boolean = false,
) {
    val isReady: Boolean get() = status == "completed" || cached || downloadFinished
    val isFailed: Boolean get() = status == "error" || status == "stalled"
}

@Serializable
data class TbCreateData(
    @SerialName("torrent_id") val torrentId: Long = 0,
    @SerialName("queued_id") val queuedId: Long? = null,
    val name: String? = null,
    val hash: String? = null,
    val detail: String? = null,
)

@Serializable
data class TbCachedItem(val hash: String? = null, val name: String? = null, val size: Long = 0)

@Serializable
data class TbUser(
    val id: Long = 0,
    val email: String? = null,
    val plan: Int = 0,
    @SerialName("is_subscribed") val isSubscribed: Boolean = false,
)

// Response envelopes (one concrete type per endpoint since `data` varies).
@Serializable
data class TbCreateResp(val success: Boolean = false, val error: String? = null, val detail: String? = null, val data: TbCreateData? = null)

@Serializable
data class TbListResp(val success: Boolean = false, val error: String? = null, val detail: String? = null, val data: List<TbTorrent>? = null)

@Serializable
data class TbCachedResp(val success: Boolean = false, val error: String? = null, val detail: String? = null, val data: List<TbCachedItem>? = null)

@Serializable
data class TbDlResp(val success: Boolean = false, val error: String? = null, val detail: String? = null, val data: String? = null)

@Serializable
data class TbUserResp(val success: Boolean = false, val error: String? = null, val detail: String? = null, val data: TbUser? = null)
