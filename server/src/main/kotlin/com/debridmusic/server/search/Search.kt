package com.debridmusic.server.search

import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable
import org.slf4j.LoggerFactory
import java.net.URLEncoder

/** One torrent hit, shared across sources + the TorBox resolve pipeline. */
@Serializable
data class SearchResult(
    val name: String = "",
    val size: Long = 0,
    val seeders: Int = 0,
    val leechers: Int = 0,
    val magnet: String = "",
    val hash: String = "",
    val source: String? = null,
    val cached: Boolean = false,
)

interface SearchSource {
    val id: String
    fun isEnabled(): Boolean
    suspend fun search(query: String): List<SearchResult>
}

fun magnetFor(hash: String, name: String): String =
    "magnet:?xt=urn:btih:${hash.lowercase()}&dn=${URLEncoder.encode(name, "UTF-8")}"

/** Fan out to every enabled source in parallel, dedupe by hash, drop junk, rank by seeders. */
class SearchAggregator(private val sources: List<SearchSource>) {
    private val log = LoggerFactory.getLogger(SearchAggregator::class.java)

    suspend fun search(query: String): List<SearchResult> = coroutineScope {
        val lists = sources.filter { it.isEnabled() }.map { src ->
            async {
                withTimeoutOrNull(SOURCE_TIMEOUT_MS) {
                    runCatching { src.search(query) }
                        .onFailure { log.warn("source {} failed: {}", src.id, it.message) }
                        .getOrDefault(emptyList())
                } ?: emptyList()
            }
        }.awaitAll()

        lists.flatten()
            .filter { it.hash.isNotBlank() && !isJunk(it.name) }
            .groupBy { it.hash.lowercase() }
            .map { (_, g) -> g.maxByOrNull { it.seeders }!! }
            .sortedByDescending { it.seeders }
    }

    private fun isJunk(name: String) = ADULT.containsMatchIn(name) || VIDEO.containsMatchIn(name)

    companion object {
        const val SOURCE_TIMEOUT_MS = 10_000L
        private val ADULT = Regex(
            "(\\bxxx\\b|\\.xxx\\.|\\bporn|brazzers|wowgirls|analvids|nubile|thisisglamour|onlyfans|hardcore|\\bmilf\\b|playboy|penthouse|kleenex|\\bsex\\.)",
            RegexOption.IGNORE_CASE,
        )
        private val VIDEO = Regex(
            "(\\b(480p|576p|720p|1080p|1080i|2160p|x264|x265|h\\.?264|h\\.?265|hevc|xvid|divx|blu-?ray|web-?dl|webrip|hdrip|hdtv|pdtv|dvdrip|remux|uhd)\\b|\\bmusic\\s*video\\b|\\bfilm\\b|\\.(mp4|mkv|avi|m4v|wmv|mov|vob)\\b)",
            RegexOption.IGNORE_CASE,
        )
    }
}
