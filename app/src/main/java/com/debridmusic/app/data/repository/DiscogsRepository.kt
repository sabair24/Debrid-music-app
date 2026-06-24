package com.debridmusic.app.data.repository

import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.remote.DiscogsAuthInterceptor
import com.debridmusic.app.data.remote.api.DiscogsApi
import com.debridmusic.app.data.remote.dto.DiscogsCollectionAlbum
import com.debridmusic.app.data.remote.dto.cleanDiscogsArtist
import com.debridmusic.app.domain.model.Album
import com.google.gson.Gson
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * The user's Discogs collection. Synced on demand from the Discogs API and cached
 * as JSON in [SettingsStore] (no Room table → no DB migration). Exposed as a Flow
 * of [Album] so the Library screen can reuse the existing album grid.
 */
@Singleton
class DiscogsRepository @Inject constructor(
    private val api: DiscogsApi,
    private val settingsStore: SettingsStore,
    private val discogsAuth: DiscogsAuthInterceptor,
) {
    private val gson = Gson()

    fun observeCollection(): Flow<List<Album>> =
        settingsStore.discogsCollectionJson.map { json -> parse(json).map { it.toAlbum() } }

    val lastSyncTime: Flow<Long> = settingsStore.discogsLastSyncTime

    /** Fetches the whole collection (paginated) and caches it. Returns the album count. */
    suspend fun fetchAndCacheCollection(nowMillis: Long): Result<Int> = runCatching {
        val token = settingsStore.discogsToken.first()
        if (token.isBlank()) error("Geen Discogs-token ingesteld")
        discogsAuth.token = token
        val username = api.identity().username ?: error("Kon Discogs-gebruiker niet bepalen")

        val all = mutableListOf<DiscogsCollectionAlbum>()
        var page = 1
        var pages = 1
        do {
            val resp = api.getCollectionReleases(username = username, page = page)
            resp.releases.orEmpty().forEach { rel ->
                val bi = rel.basicInformation ?: return@forEach
                all += DiscogsCollectionAlbum(
                    releaseId = bi.id,
                    title = bi.title?.takeIf { it.isNotBlank() } ?: "Onbekend album",
                    artist = bi.artists?.mapNotNull { it.name }?.joinToString(", ")?.cleanDiscogsArtist().orEmpty(),
                    artworkUri = bi.coverImage?.takeIf { it.isNotBlank() } ?: bi.thumb?.takeIf { it.isNotBlank() },
                    year = bi.year?.takeIf { it > 0 },
                )
            }
            pages = resp.pagination?.pages ?: 1
            page++
        } while (page <= pages && page <= MAX_PAGES)

        settingsStore.setDiscogsCollectionJson(gson.toJson(all))
        settingsStore.setDiscogsLastSyncTime(nowMillis)
        all.size
    }

    private fun parse(json: String): List<DiscogsCollectionAlbum> =
        if (json.isBlank()) emptyList()
        else runCatching {
            gson.fromJson(json, Array<DiscogsCollectionAlbum>::class.java)?.toList() ?: emptyList()
        }.getOrDefault(emptyList())

    private fun DiscogsCollectionAlbum.toAlbum(): Album = Album(
        id = releaseId,
        title = title,
        artistName = artist,
        artistId = 0L,
        year = year,
        artworkUri = artworkUri,
        trackCount = 0,
        genre = null,
        musicBrainzId = null,
    )

    private companion object {
        // Safety cap: 20 pages × 100 = up to 2000 albums.
        const val MAX_PAGES = 20
    }
}
