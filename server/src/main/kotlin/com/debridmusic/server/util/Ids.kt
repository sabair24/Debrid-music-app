package com.debridmusic.server.util

import java.security.MessageDigest

/** Stable, content-free ids so re-scans and ingests produce the same ids for the same files. */
object Ids {
    fun of(kind: String, value: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("$kind:${value.lowercase().trim()}".toByteArray(Charsets.UTF_8))
        return digest.take(12).joinToString("") { "%02x".format(it) }
    }

    fun track(rootIndex: Int, relPath: String) = of("track", "$rootIndex $relPath")
    fun artist(name: String) = of("artist", name)
    fun album(artist: String, album: String) = of("album", "$artist $album")
}
