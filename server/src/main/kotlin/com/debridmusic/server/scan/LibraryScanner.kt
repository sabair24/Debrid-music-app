package com.debridmusic.server.scan

import com.debridmusic.server.index.IndexStore
import com.debridmusic.server.index.ScannedTrack
import com.debridmusic.server.util.Ids
import org.jaudiotagger.audio.AudioFileIO
import org.jaudiotagger.tag.FieldKey
import org.slf4j.LoggerFactory
import java.io.File
import java.util.logging.Level
import java.util.logging.Logger

/** Walks the music roots, reads tags and rebuilds the index. Idempotent. */
class LibraryScanner(
    private val roots: List<File>,
    private val store: IndexStore,
) {
    private val log = LoggerFactory.getLogger(LibraryScanner::class.java)

    init {
        // JAudioTagger logs noisily at INFO on every file; quiet it down.
        Logger.getLogger("org.jaudiotagger").level = Level.WARNING
    }

    @Synchronized
    fun scan(): Int {
        val started = System.currentTimeMillis()
        val tracks = ArrayList<ScannedTrack>()
        roots.forEachIndexed { rootIndex, root ->
            if (!root.isDirectory) {
                log.warn("Music root does not exist: {}", root); return@forEachIndexed
            }
            root.walkTopDown()
                .filter { it.isFile && it.extension.lowercase() in AUDIO_EXTS }
                .forEach { file ->
                    runCatching { readTrack(file, root, rootIndex) }
                        .onSuccess { tracks += it }
                        .onFailure { log.warn("Skipping unreadable file {}: {}", file, it.message) }
                }
        }
        store.replaceAll(tracks, started)
        log.info("Scanned {} tracks in {} ms", tracks.size, System.currentTimeMillis() - started)
        return tracks.size
    }

    private fun readTrack(file: File, root: File, rootIndex: Int): ScannedTrack {
        val relPath = root.toPath().relativize(file.toPath()).toString().replace(File.separatorChar, '/')
        val audio = AudioFileIO.read(file)
        val header = audio.audioHeader
        val tag = audio.tag

        fun field(key: FieldKey): String? =
            runCatching { tag?.getFirst(key)?.trim()?.takeIf { it.isNotEmpty() } }.getOrNull()

        val title = field(FieldKey.TITLE) ?: file.nameWithoutExtension
        val artist = field(FieldKey.ALBUM_ARTIST) ?: field(FieldKey.ARTIST) ?: "Unknown Artist"
        val album = field(FieldKey.ALBUM) ?: file.parentFile?.name ?: "Unknown Album"
        val trackNo = field(FieldKey.TRACK)?.let { parseLeadingInt(it) } ?: 0
        val discNo = field(FieldKey.DISC_NO)?.let { parseLeadingInt(it) } ?: 1
        val year = field(FieldKey.YEAR)?.let { Regex("\\d{4}").find(it)?.value?.toIntOrNull() }
        val genre = field(FieldKey.GENRE)

        val ext = file.extension.lowercase()

        return ScannedTrack(
            id = Ids.track(rootIndex, relPath),
            albumId = Ids.album(artist, album),
            artistId = Ids.artist(artist),
            title = title,
            artistName = artist,
            albumTitle = album,
            trackNo = trackNo,
            discNo = discNo.coerceAtLeast(1),
            durationMs = (header?.trackLength ?: 0).toLong() * 1000L,
            bitrate = runCatching { header?.bitRateAsNumber?.toInt() }.getOrNull(),
            sampleRate = runCatching { header?.sampleRateAsNumber }.getOrNull(),
            lossless = ext in LOSSLESS_EXTS,
            sizeBytes = file.length(),
            year = year,
            genre = genre,
            mime = MIME_TYPES[ext],
            rootIndex = rootIndex,
            relPath = relPath,
        )
    }

    private fun parseLeadingInt(s: String): Int =
        Regex("\\d+").find(s)?.value?.toIntOrNull() ?: 0

    companion object {
        val AUDIO_EXTS = setOf("flac", "mp3", "m4a", "aac", "ogg", "opus", "wav", "aiff", "aif", "wma", "alac", "ape", "wv")
        val LOSSLESS_EXTS = setOf("flac", "wav", "aiff", "aif", "alac", "ape", "wv")
        val MIME_TYPES = mapOf(
            "flac" to "audio/flac", "mp3" to "audio/mpeg", "m4a" to "audio/mp4", "aac" to "audio/aac",
            "ogg" to "audio/ogg", "opus" to "audio/opus", "wav" to "audio/wav", "aiff" to "audio/aiff",
            "aif" to "audio/aiff", "wma" to "audio/x-ms-wma", "alac" to "audio/mp4", "ape" to "audio/x-ape",
            "wv" to "audio/x-wavpack",
        )
    }
}
