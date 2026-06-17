package com.debridmusic.app.search.sources

import com.debridmusic.app.data.remote.api.ApibayApi
import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.search.SearchSource
import com.debridmusic.app.search.magnetFor
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ApibaySource @Inject constructor(
    private val api: ApibayApi,
) : SearchSource {
    override val id = "apibay"

    override suspend fun search(query: String): List<TorBoxSearchResult> {
        return api.search(query)
            .filterNot { it.isNoResults }
            // apibay's cat filter is loose and leaks video/porn (cat 500); keep only
            // the Audio range (100–199: Audio/Music/Audiobooks/FLAC/…).
            .filter { (it.category?.toIntOrNull() ?: 0) in 100..199 }
            .mapNotNull { r ->
                val hash = r.infoHash ?: return@mapNotNull null
                val name = r.name ?: return@mapNotNull null
                TorBoxSearchResult(
                    rawTitle = name, name = name,
                    size = r.size?.toLongOrNull() ?: 0L,
                    seeders = r.seeders?.toIntOrNull() ?: 0,
                    leechers = r.leechers?.toIntOrNull() ?: 0,
                    magnet = magnetFor(hash, name), hash = hash.lowercase(),
                    source = "Pirate Bay",
                )
            }
    }
}
