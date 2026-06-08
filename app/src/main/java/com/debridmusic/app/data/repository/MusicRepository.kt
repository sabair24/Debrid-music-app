package com.debridmusic.app.data.repository

import com.debridmusic.app.data.local.dao.AlbumDao
import com.debridmusic.app.data.local.dao.AlbumWithCount
import com.debridmusic.app.data.local.dao.ArtistDao
import com.debridmusic.app.data.local.dao.TrackDao
import com.debridmusic.app.data.local.entity.AlbumEntity
import com.debridmusic.app.data.local.entity.ArtistEntity
import com.debridmusic.app.data.local.entity.TrackEntity
import com.debridmusic.app.domain.model.Album
import com.debridmusic.app.domain.model.Artist
import com.debridmusic.app.domain.model.Track
import com.debridmusic.app.scanner.MediaScanner
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MusicRepository @Inject constructor(
    private val trackDao: TrackDao,
    private val albumDao: AlbumDao,
    private val artistDao: ArtistDao,
    private val mediaScanner: MediaScanner,
) {
    fun observeTracks(): Flow<List<Track>> =
        trackDao.observeAll().map { list -> list.map { it.toDomain() } }

    fun observeRecentlyAdded(limit: Int = 20): Flow<List<Track>> =
        trackDao.observeRecentlyAdded(limit).map { list -> list.map { it.toDomain() } }

    fun observeAlbums(): Flow<List<Album>> =
        albumDao.observeAlbumsWithTrackCount().map { list -> list.map { it.toDomain() } }

    fun observeArtists(): Flow<List<Artist>> =
        artistDao.observeArtistsWithTracks().map { list -> list.map { it.toDomain() } }

    fun observeTracksByAlbum(albumId: Long): Flow<List<Track>> =
        trackDao.observeByAlbum(albumId).map { list -> list.map { it.toDomain() } }

    fun observeTracksByArtist(artistId: Long): Flow<List<Track>> =
        trackDao.observeByArtist(artistId).map { list -> list.map { it.toDomain() } }

    suspend fun search(query: String): List<Track> =
        trackDao.search(query).map { it.toDomain() }

    fun trackCount(): Flow<Int> = trackDao.countAll()

    suspend fun scanLocalMedia(): Int = mediaScanner.scanDevice()

    suspend fun getTrack(id: Long): Track? = trackDao.getById(id)?.toDomain()

    suspend fun getAlbum(id: Long): Album? = albumDao.getById(id)?.toDomain()

    suspend fun getArtist(id: Long): Artist? = artistDao.getById(id)?.toDomain()
}

// ---------- mapping extensions ----------

fun TrackEntity.toDomain() = Track(
    id = id,
    title = title,
    artistName = artistName,
    albumTitle = albumTitle,
    albumId = albumId ?: 0L,
    artistId = artistId ?: 0L,
    uri = uri,
    durationMs = durationMs,
    trackNumber = trackNumber,
    discNumber = discNumber,
    year = year,
    artworkUri = artworkUri,
    genre = genre,
    bitrate = bitrate,
    sampleRate = sampleRate,
    isLossless = isLossless,
    fileSize = fileSize,
    dateAdded = dateAdded,
)

fun AlbumWithCount.toDomain() = Album(
    id = id,
    title = title,
    artistName = artistName,
    artistId = artistId,
    year = year,
    artworkUri = artworkUri,
    trackCount = trackCount,
    genre = genre,
    musicBrainzId = musicBrainzId,
)

fun AlbumEntity.toDomain() = Album(
    id = id,
    title = title,
    artistName = artistName,
    artistId = artistId,
    year = year,
    artworkUri = artworkUri,
    trackCount = 0,
    genre = genre,
    musicBrainzId = musicBrainzId,
)

fun ArtistEntity.toDomain() = Artist(
    id = id,
    name = name,
    biography = biography,
    imageUri = imageUri,
    musicBrainzId = musicBrainzId,
    albumCount = 0,
)
