package com.debridmusic.server.service

import com.debridmusic.server.index.IndexStore
import org.jaudiotagger.audio.AudioFileIO
import java.io.File

class Artwork(val bytes: ByteArray, val contentType: String)

/**
 * Resolves album cover art: embedded tag picture first, else cover/folder image in the
 * album dir, else a web-fetched cover cached by the enrichment service ([artCacheDir]).
 */
class ArtworkService(
    private val roots: List<File>,
    private val store: IndexStore,
    private val artCacheDir: File = File("."),
) {
    /** Full resolution incl. the enrichment cache — used to serve /art. */
    fun forAlbum(albumId: String): Artwork? = localArt(albumId) ?: cachedArt(albumId)

    /** Cached web cover written by the enrichment service, if any. */
    fun cachedArt(albumId: String): Artwork? =
        File(artCacheDir, "$albumId.jpg").takeIf { it.isFile }?.let { Artwork(it.readBytes(), "image/jpeg") }

    /** True when the album has embedded/folder art locally (no network needed). */
    fun hasLocalArt(albumId: String): Boolean = localArt(albumId) != null

    /** Embedded picture or a folder cover image; null if the album has neither. */
    fun localArt(albumId: String): Artwork? {
        val track = store.firstTrackOfAlbum(albumId) ?: return null
        val file = File(roots.getOrNull(track.rootIndex) ?: return null, track.relPath)
        if (!file.isFile) return null

        // 1. Embedded artwork.
        runCatching {
            val art = AudioFileIO.read(file).tag?.firstArtwork
            if (art != null) {
                val data = art.binaryData
                if (data != null && data.isNotEmpty()) {
                    return Artwork(data, art.mimeType?.takeIf { it.isNotBlank() } ?: "image/jpeg")
                }
            }
        }

        // 2. cover.jpg / folder.jpg / front.* alongside the audio.
        val dir = file.parentFile ?: return null
        val cover = COVER_NAMES.firstNotNullOfOrNull { name ->
            dir.listFiles { f -> f.isFile && f.name.lowercase() == name }?.firstOrNull()
        } ?: dir.listFiles { f -> f.isFile && f.extension.lowercase() in IMAGE_EXTS && f.nameWithoutExtension.lowercase() in COVER_STEMS }?.firstOrNull()

        return cover?.let { Artwork(it.readBytes(), mimeForImage(it.extension)) }
    }

    private fun mimeForImage(ext: String) = when (ext.lowercase()) {
        "png" -> "image/png"; "webp" -> "image/webp"; "gif" -> "image/gif"; else -> "image/jpeg"
    }

    companion object {
        val COVER_NAMES = listOf("cover.jpg", "cover.png", "folder.jpg", "folder.png", "front.jpg", "front.png")
        val COVER_STEMS = setOf("cover", "folder", "front", "album", "albumart")
        val IMAGE_EXTS = setOf("jpg", "jpeg", "png", "webp")
    }
}
