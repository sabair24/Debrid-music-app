package com.debridmusic.app.soulseek

/**
 * Soulseek shares are folders, so the file path usually encodes real metadata:
 *   ...\Artist\Album\01 - Track Title.flac
 * We parse artist/album/title from that path so downloads land in the library
 * with usable tags (instead of the uploader's username), which is what the
 * MusicBrainz / Last.fm enrichment then matches against.
 */
data class ParsedTrackMeta(
    val title: String,
    val artist: String,
    val album: String,
)

object SoulseekPath {
    fun parse(rawPath: String): ParsedTrackMeta {
        val segments = rawPath
            .replace('\\', '/')
            .split('/')
            .map { it.trim() }
            .filter { it.isNotBlank() }

        val fileSeg = segments.lastOrNull().orEmpty()
        val title = cleanTitle(fileSeg.substringBeforeLast('.', fileSeg))

        // Album = parent folder; artist = grandparent folder, when present.
        val album = segments.getOrNull(segments.size - 2)?.let { cleanFolder(it) }.orEmpty()
        val artist = segments.getOrNull(segments.size - 3)?.let { cleanFolder(it) }.orEmpty()

        return ParsedTrackMeta(title = title, artist = artist, album = album)
    }

    // "01 - Title", "01. Title", "01 Title", "A1 Title" -> "Title"
    private fun cleanTitle(name: String): String =
        name.replace(Regex("^\\s*[A-Za-z]?\\d{1,3}\\s*[-._)]?\\s*"), "")
            .replace('_', ' ')
            .trim()
            .ifBlank { name.trim() }

    // Strip common noise from folder names: "(2019) Album [FLAC]" -> "Album"
    private fun cleanFolder(name: String): String =
        name.replace(Regex("\\[[^\\]]*\\]"), " ")          // [FLAC], [320]
            .replace(Regex("\\((?:19|20)\\d{2}\\)"), " ")   // (2019)
            .replace(Regex("\\b(?:19|20)\\d{2}\\b"), " ")    // bare year
            .replace(Regex("(?i)\\b(flac|mp3|320|256|192|kbps|cd\\d*|vinyl|web|remaster(ed)?)\\b"), " ")
            .replace('_', ' ')
            .replace(Regex("\\s+"), " ")
            .trim(' ', '-', '_', '.')
            .trim()
}
