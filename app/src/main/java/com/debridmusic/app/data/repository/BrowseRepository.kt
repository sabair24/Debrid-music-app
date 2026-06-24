package com.debridmusic.app.data.repository

import com.debridmusic.app.data.remote.api.DeezerApi
import com.debridmusic.app.data.remote.dto.DeezerAlbum
import com.debridmusic.app.data.remote.dto.DeezerTrack
import com.debridmusic.app.data.remote.dto.bestCover
import com.debridmusic.app.data.remote.dto.bestImage
import com.debridmusic.app.domain.model.ArtistDiscography
import com.debridmusic.app.domain.model.BrowseAlbum
import com.debridmusic.app.domain.model.BrowseArtist
import com.debridmusic.app.domain.model.BrowseTrack
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import javax.inject.Inject
import javax.inject.Singleton

/**
 * "Stremio-for-music" browse data, sourced from the keyless Deezer API: search
 * artists, list an artist's albums/singles/top-tracks, and an album's tracklist.
 * Actual playback is resolved to torrents separately (see BrowsePlayer).
 */
@Singleton
class BrowseRepository @Inject constructor(
    private val deezerApi: DeezerApi,
) {
    suspend fun searchArtists(query: String): List<BrowseArtist> = runCatching {
        deezerApi.searchArtist(query, limit = 20).data.orEmpty().mapNotNull { a ->
            val name = a.name ?: return@mapNotNull null
            BrowseArtist(a.id, name, a.bestImage())
        }
    }.getOrDefault(emptyList())

    suspend fun artistDiscography(artistId: Long): ArtistDiscography = coroutineScope {
        val artistD = async { runCatching { deezerApi.getArtist(artistId) }.getOrNull() }
        val albumsD = async { runCatching { deezerApi.artistAlbums(artistId).data.orEmpty() }.getOrDefault(emptyList()) }
        val topD = async { runCatching { deezerApi.artistTopTracks(artistId).data.orEmpty() }.getOrDefault(emptyList()) }

        val deezerArtist = artistD.await()
        val artistName = deezerArtist?.name ?: ""
        val header = deezerArtist?.let { BrowseArtist(it.id, artistName, it.bestImage()) }

        val all = albumsD.await()
        val albums = all.filter { !it.isSingle() }
            .map { it.toBrowseAlbum(artistName) }
            .distinctBy { it.title.lowercase() }
        val singles = all.filter { it.isSingle() }
            .map { it.toBrowseAlbum(artistName) }
            .distinctBy { it.title.lowercase() }
        val top = topD.await().mapNotNull { it.toBrowseTrack(artistName) }

        ArtistDiscography(header, albums, singles, top)
    }

    suspend fun albumWithTracks(albumId: Long): Pair<BrowseAlbum?, List<BrowseTrack>> = coroutineScope {
        val albumD = async { runCatching { deezerApi.getAlbum(albumId) }.getOrNull() }
        val tracksD = async { runCatching { deezerApi.albumTracks(albumId).data.orEmpty() }.getOrDefault(emptyList()) }

        val album = albumD.await()
        val artistName = album?.artist?.name ?: ""
        val header = album?.let {
            BrowseAlbum(it.id, it.title ?: "", artistName, it.bestCover(), it.year(), it.isSingle())
        }
        val tracks = tracksD.await().mapIndexedNotNull { i, t ->
            val title = t.title ?: return@mapIndexedNotNull null
            BrowseTrack(
                id = t.id, title = title,
                artist = t.artist?.name ?: artistName,
                album = album?.title ?: "",
                albumId = albumId,
                artworkUri = header?.artworkUri,
                position = t.trackPosition ?: (i + 1),
            )
        }
        header to tracks
    }

    private fun DeezerAlbum.isSingle(): Boolean = recordType?.equals("single", ignoreCase = true) == true
    private fun DeezerAlbum.year(): Int? = releaseDate?.take(4)?.toIntOrNull()

    private fun DeezerAlbum.toBrowseAlbum(artistName: String): BrowseAlbum = BrowseAlbum(
        id = id,
        title = title ?: "",
        artist = artist?.name ?: artistName,
        artworkUri = bestCover(),
        year = year(),
        isSingle = isSingle(),
    )

    private fun DeezerTrack.toBrowseTrack(artistName: String): BrowseTrack? {
        val t = title ?: return null
        return BrowseTrack(
            id = id, title = t,
            artist = artist?.name ?: artistName,
            album = album?.title ?: "",
            albumId = album?.id ?: 0L,
            artworkUri = album?.bestCover(),
            position = trackPosition ?: 0,
        )
    }
}
