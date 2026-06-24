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
            // Knaben can return entries with a missing/blank/malformed infohash; without a
            // valid one TorBox can never resolve the magnet, leaving the row stuck on
            // "Adding to TorBox…". Drop those rather than surface a dead result.
            val hash = hit.hash?.trim()?.takeIf { INFOHASH.matches(it) }?.lowercase()
                ?: return@mapNotNull null
            val title = hit.title ?: return@mapNotNull null
            TorBoxSearchResult(
                rawTitle = title, name = title,
                size = hit.bytes ?: 0L,
                seeders = hit.seeders ?: 0,
                leechers = hit.peers ?: 0,
                magnet = hit.magnetUrl?.takeIf { it.isNotBlank() } ?: magnetFor(hash, title),
                hash = hash,
                source = "Knaben",
            )
        }
    }

    private companion object {
        // 40-char hex (SHA-1) or 32-char base32 infohash.
        val INFOHASH = Regex("^([0-9a-fA-F]{40}|[A-Za-z2-7]{32})$")
    }
}
