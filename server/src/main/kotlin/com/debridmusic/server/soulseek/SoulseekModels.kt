package com.debridmusic.server.soulseek

import kotlinx.serialization.Serializable

/** One file offered by a Soulseek peer. Sent to the web UI and back for download. */
@Serializable
data class SoulseekFile(
    val username: String,
    val filename: String,          // full remote path, backslash-separated
    val size: Long,
    val speed: Int = 0,            // peer avg speed
    val queueLength: Int = 0,
    val freeSlots: Boolean = false,
    val bitrate: Int? = null,
    val durationSec: Int? = null,
    val sampleRate: Int? = null,
    val bitDepth: Int? = null,
    val isVbr: Boolean = false,
) {
    val displayName: String get() = filename.replace('\\', '/').substringAfterLast('/')
    val extension: String get() = displayName.substringAfterLast('.', "").lowercase()
    val isFlac: Boolean get() = extension == "flac"
    val isAudio: Boolean get() = extension in AUDIO_EXTS

    companion object {
        val AUDIO_EXTS = setOf("flac", "mp3", "m4a", "ogg", "opus", "wav", "aac", "alac", "ape")
    }
}
