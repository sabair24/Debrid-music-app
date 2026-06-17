package com.debridmusic.app.search.sources

import com.debridmusic.app.data.remote.api.BitSearchApi
import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.search.SearchSource
import com.debridmusic.app.search.magnetFor
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class BitSearchSource @Inject constructor(
    private val api: BitSearchApi,
) : SearchSource {
    override val id = "bitsearch"

    override suspend fun search(query: String): List<TorBoxSearchResult> {
        val resp = api.search(query)
        if (!resp.success) return emptyList()
        return resp.results.orEmpty()
            .filter { it.infohash.isNotBlank() }
            .map { r ->
                TorBoxSearchResult(
                    rawTitle = r.title, name = r.title, size = r.size,
                    seeders = r.seeders, leechers = r.leechers,
                    magnet = magnetFor(r.infohash, r.title), hash = r.infohash.lowercase(),
                    source = "BitSearch",
                )
            }
    }
}
