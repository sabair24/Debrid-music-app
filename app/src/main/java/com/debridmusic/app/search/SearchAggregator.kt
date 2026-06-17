package com.debridmusic.app.search

import android.util.Log
import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.search.sources.ApibaySource
import com.debridmusic.app.search.sources.BitSearchSource
import com.debridmusic.app.search.sources.KnabenSource
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeoutOrNull
import javax.inject.Inject
import javax.inject.Singleton

/**
 * "Stremio-for-music": queries every enabled torrent source in parallel, dedupes
 * by infohash (keeping the highest-seeder copy), and sorts by seeders. One slow
 * or broken source can never sink the whole search.
 */
@Singleton
class SearchAggregator @Inject constructor(
    bitSearch: BitSearchSource,
    apibay: ApibaySource,
    knaben: KnabenSource,
) {
    private val sources: List<SearchSource> = listOf(apibay, bitSearch, knaben)

    suspend fun search(query: String): List<TorBoxSearchResult> = coroutineScope {
        val perSource = sources.map { source ->
            async {
                if (!source.isEnabled()) return@async emptyList()
                withTimeoutOrNull(SOURCE_TIMEOUT_MS) {
                    runCatching { source.search(query) }
                        .onFailure { Log.d(TAG, "${source.id} failed: ${it.message}") }
                        .getOrDefault(emptyList())
                } ?: emptyList<TorBoxSearchResult>().also { Log.d(TAG, "${source.id} timed out") }
            }
        }.awaitAll().flatten()

        // Dedupe by infohash (keep the highest-seeder copy), drop non-music junk, sort.
        perSource
            .filter { it.hash.isNotBlank() && !it.name.isJunk() }
            .groupBy { it.hash.lowercase() }
            .map { (_, dupes) -> dupes.maxByOrNull { it.seeders }!! }
            .sortedByDescending { it.seeders }
    }

    // Indexer "audio" categories leak adult/video releases; filter the obvious ones.
    private fun String.isJunk(): Boolean = ADULT.containsMatchIn(this) || VIDEO.containsMatchIn(this)

    companion object {
        private const val TAG = "SearchAggregator"
        private const val SOURCE_TIMEOUT_MS = 15_000L
        private val ADULT = Regex(
            "(?i)(\\bxxx\\b|\\.xxx\\.|\\bporn|brazzers|wowgirls|analvids|nubile|thisisglamour|" +
                "onlyfans|hardcore|\\bmilf\\b|playboy|penthouse|kleenex|\\bsex\\.)",
        )
        private val VIDEO = Regex("(?i)(\\b(480p|720p|1080p|2160p|x264|x265|hevc|bluray|web-?dl|hdrip|dvdrip)\\b|\\.(mp4|mkv|avi)\\b)")
    }
}
