package com.debridmusic.app.metadata

import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.local.dao.AlbumDao
import com.debridmusic.app.data.local.dao.ArtistDao
import com.debridmusic.app.data.local.dao.TrackDao
import com.debridmusic.app.data.local.entity.AlbumEntity
import com.debridmusic.app.data.local.entity.ArtistEntity
import com.debridmusic.app.data.remote.api.CoverArtArchiveApi
import com.debridmusic.app.data.remote.api.LastFmApi
import com.debridmusic.app.data.remote.api.MusicBrainzApi
import com.debridmusic.app.data.remote.dto.bestFrontUrl
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import javax.inject.Inject
import javax.inject.Singleton

data class EnrichmentProgress(
    val current: Int,
    val total: Int,
    val currentItem: String = "",
) {
    val isDone get() = current >= total
    val fraction get() = if (total > 0) current.toFloat() / total else 0f
}

@Singleton
class MetadataEnricher @Inject constructor(
    private val albumDao: AlbumDao,
    private val artistDao: ArtistDao,
    private val trackDao: TrackDao,
    private val musicBrainzApi: MusicBrainzApi,
    private val coverArtApi: CoverArtArchiveApi,
    private val lastFmApi: LastFmApi,
    private val settingsStore: SettingsStore,
) {
    suspend fun enrichAll(
        onProgress: suspend (EnrichmentProgress) -> Unit = {},
    ): Int {
        var enriched = 0
        val albums = albumDao.observeAll().first()
        val artists = artistDao.observeAll().first()
        val total = albums.size + artists.size

        albums.forEachIndexed { idx, album ->
            onProgress(EnrichmentProgress(idx, total, album.title))
            if (enrichAlbum(album)) enriched++
            delay(MB_RATE_LIMIT_MS)
        }

        val lastFmKey = settingsStore.lastFmApiKey.first()
        artists.forEachIndexed { idx, artist ->
            onProgress(EnrichmentProgress(albums.size + idx, total, artist.name))
            if (enrichArtist(artist, lastFmKey)) enriched++
            if (lastFmKey.isNotBlank()) delay(LASTFM_RATE_LIMIT_MS)
        }

        onProgress(EnrichmentProgress(total, total))
        return enriched
    }

    private suspend fun enrichAlbum(album: AlbumEntity): Boolean {
        if (album.artworkUri != null && album.musicBrainzId != null) return false

        return try {
            // Search MusicBrainz for the release
            val query = buildMbReleaseQuery(album.title, album.artistName)
            val result = musicBrainzApi.searchRelease(query)
            val best = result.releases
                ?.maxByOrNull { it.score ?: 0 }
                ?: return false

            val mbid = best.id
            val year = best.date?.take(4)?.toIntOrNull() ?: album.year

            // Fetch cover art from Cover Art Archive
            val artworkUrl = if (album.artworkUri == null) {
                try {
                    val coverArt = coverArtApi.getCoverArt(mbid)
                    coverArt.bestFrontUrl()
                } catch (_: Exception) { null }
            } else album.artworkUri

            albumDao.update(
                album.copy(
                    musicBrainzId = mbid,
                    artworkUri = artworkUrl ?: album.artworkUri,
                    year = year ?: album.year,
                    genre = album.genre
                        ?: best.releaseGroup?.primaryType?.lowercase()?.replaceFirstChar { it.uppercase() },
                )
            )

            // Propagate artwork to tracks in this album that have no artwork
            if (artworkUrl != null) {
                val tracks = trackDao.observeByAlbum(album.id).first()
                tracks.filter { it.artworkUri == null }.forEach { track ->
                    trackDao.update(track.copy(artworkUri = artworkUrl))
                }
            }
            true
        } catch (_: Exception) { false }
    }

    private suspend fun enrichArtist(artist: ArtistEntity, lastFmApiKey: String): Boolean {
        if (artist.biography != null && artist.imageUri != null) return false

        var updated = false

        // MusicBrainz — get MBID
        if (artist.musicBrainzId == null) {
            try {
                val result = musicBrainzApi.searchArtist("artist:\"${artist.name}\"")
                val best = result.artists?.maxByOrNull { it.score ?: 0 }
                if (best != null) {
                    artistDao.update(artist.copy(musicBrainzId = best.id))
                    updated = true
                }
            } catch (_: Exception) { }
        }

        // Last.fm — bio + image
        if (lastFmApiKey.isNotBlank() && (artist.biography == null || artist.imageUri == null)) {
            try {
                delay(LASTFM_RATE_LIMIT_MS)
                val response = lastFmApi.getArtistInfo(artist = artist.name, apiKey = lastFmApiKey)
                val lfmArtist = response.artist ?: return updated

                val bio = lfmArtist.bio?.summary?.stripHtml()?.trimLastFmSuffix()
                val imageUrl = lfmArtist.image
                    ?.lastOrNull { it.url.isNotBlank() && it.size == "extralarge" }?.url
                    ?: lfmArtist.image?.lastOrNull { it.url.isNotBlank() }?.url

                val current = artistDao.getById(artist.id) ?: return updated
                artistDao.update(
                    current.copy(
                        biography = bio?.takeIf { it.isNotBlank() } ?: current.biography,
                        imageUri = imageUrl?.takeIf { it.isNotBlank() } ?: current.imageUri,
                        musicBrainzId = current.musicBrainzId ?: lfmArtist.mbid?.takeIf { it.isNotBlank() },
                    )
                )
                updated = true
            } catch (_: Exception) { }
        }

        return updated
    }

    private fun buildMbReleaseQuery(albumTitle: String, artistName: String): String {
        val cleanAlbum = albumTitle.replace("\"", "\\\"")
        val cleanArtist = artistName.replace("\"", "\\\"")
        return "release:\"$cleanAlbum\" AND artist:\"$cleanArtist\""
    }

    companion object {
        private const val MB_RATE_LIMIT_MS = 1100L
        private const val LASTFM_RATE_LIMIT_MS = 250L
    }
}

private fun String.stripHtml(): String =
    replace(Regex("<[^>]+>"), "").replace("&amp;", "&").replace("&quot;", "\"")
        .replace("&lt;", "<").replace("&gt;", ">").replace("&apos;", "'")
        .replace(Regex("\\s+"), " ").trim()

private fun String.trimLastFmSuffix(): String {
    val cutMarker = "<a href=\"https://www.last.fm"
    val idx = indexOf(cutMarker)
    return if (idx > 0) substring(0, idx).trim().trimEnd('.').trim() else this
}
