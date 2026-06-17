package com.debridmusic.app.search.sources

import com.debridmusic.app.data.remote.api.KnabenApi
import com.debridmusic.app.data.remote.dto.KnabenRequest
import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.search.SearchSource
import com.debridmusic.app.search.magnetFor
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class KnabenSource @Inject constructor(
    private val api: KnabenApi,
) : SearchSource {
    override val id = "knaben"

    override suspend fun search(query: String): List<TorBoxSearchResult> {
        val resp = api.search(KnabenRequest(query = query))
        return resp.hits.orEmpty().mapNotNull { hit ->
            val hash = hit.hash ?: return@mapNotNull null
            val title = hit.title ?: return@mapNotNull null
            TorBoxSearchResult(
                rawTitle = title, name = title,
                size = hit.bytes ?: 0L,
                seeders = hit.seeders ?: 0,
                leechers = hit.peers ?: 0,
                magnet = hit.magnetUrl?.takeIf { it.isNotBlank() } ?: magnetFor(hash, title),
                hash = hash.lowercase(),
                source = "Knaben",
            )
        }
    }
}
