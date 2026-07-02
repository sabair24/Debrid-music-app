package com.debridmusic.server.soulseek

/** artist/album/title parsed from a Soulseek remote path (backslash-separated). */
data class ParsedTrackMeta(val title: String, val artist: String, val album: String)

object SoulseekPath {
    private val TRACK_PREFIX = Regex("^([A-Da-d]?\\d{1,3})[.\\-)\\s]+")
    private val NOISE = Regex("\\[[^]]*]|\\((?:19|20)\\d{2}\\)|\\b(?:19|20)\\d{2}\\b|\\b(flac|mp3|320|v0|web|cd|vinyl|lossless|24bit|16bit)\\b", RegexOption.IGNORE_CASE)

    fun parse(rawPath: String): ParsedTrackMeta {
        val parts = rawPath.replace('\\', '/').split('/').map { it.trim() }.filter { it.isNotEmpty() }
        val fileName = parts.lastOrNull().orEmpty()
        val album = parts.getOrNull(parts.size - 2)?.let { clean(it) }.orEmpty()
        val artist = parts.getOrNull(parts.size - 3)?.let { clean(it) }.orEmpty()
        val title = fileName.substringBeforeLast('.', fileName).replace(TRACK_PREFIX, "").trim()
        return ParsedTrackMeta(title.ifEmpty { fileName }, artist, album)
    }

    private fun clean(s: String) = s.replace(NOISE, "").replace(Regex("\\s{2,}"), " ").trim(' ', '-', '_', '.')
}
