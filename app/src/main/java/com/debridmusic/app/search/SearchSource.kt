package com.debridmusic.app.search

import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import java.net.URLEncoder

/**
 * A torrent indexer. Each source returns normalized [TorBoxSearchResult]s (with a
 * magnet built from the infohash) so they can be merged and all resolved through
 * the existing TorBox add-magnet → stream flow.
 */
interface SearchSource {
    val id: String
    /** Disabled sources (e.g. RuTracker without credentials) are skipped. */
    suspend fun isEnabled(): Boolean = true
    suspend fun search(query: String): List<TorBoxSearchResult>
}

/** Builds a magnet link from an infohash + display name. */
fun magnetFor(infohash: String, name: String): String {
    val dn = runCatching { URLEncoder.encode(name, "UTF-8") }.getOrDefault(name)
    return "magnet:?xt=urn:btih:${infohash.lowercase()}&dn=$dn"
}
