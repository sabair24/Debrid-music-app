package com.debridmusic.app.data.repository

import com.debridmusic.app.data.local.dao.AlbumDao
import com.debridmusic.app.data.local.dao.AlbumWithCount
import com.debridmusic.app.data.local.dao.ArtistDao
import com.debridmusic.app.data.local.dao.DownloadDao
import com.debridmusic.app.data.local.dao.PlaylistDao
import com.debridmusic.app.data.local.dao.TrackDao
import com.debridmusic.app.data.local.entity.AlbumEntity
import com.debridmusic.app.data.local.entity.ArtistEntity
import com.debridmusic.app.data.local.entity.DownloadEntity
import com.debridmusic.app.data.local.entity.DownloadStatus
import com.debridmusic.app.data.local.entity.PlaylistEntity
import com.debridmusic.app.data.local.entity.PlaylistTrackCrossRef
import com.debridmusic.app.data.local.entity.TrackEntity
import com.debridmusic.app.domain.model.Album
import com.debridmusic.app.domain.model.Artist
import com.debridmusic.app.domain.model.Download
import com.debridmusic.app.domain.model.Playlist
import com.debridmusic.app.domain.model.Track
import com.debridmusic.app.metadata.MetadataEnricher
import com.debridmusic.app.scanner.MediaScanner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MusicRepository @Inject constructor(
    private val trackDao: TrackDao,
    private val albumDao: AlbumDao,
    private val artistDao: ArtistDao,
    private val playlistDao: PlaylistDao,
    private val downloadDao: DownloadDao,
    private val mediaScanner: MediaScanner,
    private val enricher: MetadataEnricher,
    private val appScope: CoroutineScope,
) {
    private val enrichMutex = Mutex()
    // ── Library ───────────────────────────────────────────────────────────────
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

    suspend fun search(query: String): List<Track> = trackDao.search(query).map { it.toDomain() }

    fun trackCount(): Flow<Int> = trackDao.countAll()

    suspend fun scanLocalMedia(): Int {
        val count = mediaScanner.scanDevice()
        enrichInBackground() // auto-fetch artwork/bios/descriptions, non-blocking
        return count
    }

    /** Fire-and-forget metadata enrichment; guarded so passes never overlap. */
    fun enrichInBackground() {
        appScope.launch {
            if (enrichMutex.tryLock()) {
                try { enricher.enrichAll() } finally { enrichMutex.unlock() }
            }
        }
    }

    suspend fun getTrack(id: Long): Track? = trackDao.getById(id)?.toDomain()

    suspend fun getAlbum(id: Long): Album? = albumDao.getById(id)?.toDomain()

    suspend fun getArtist(id: Long): Artist? = artistDao.getById(id)?.toDomain()

    // ── Playlists ─────────────────────────────────────────────────────────────
    fun observePlaylists(): Flow<List<Playlist>> =
        playlistDao.observeAllWithCount().map { list ->
            list.map { Playlist(it.id, it.name, it.trackCount, it.createdAt) }
        }

    suspend fun createPlaylist(name: String): Long =
        playlistDao.insert(PlaylistEntity(name = name))

    suspend fun deletePlaylist(id: Long) = playlistDao.deleteById(id)

    suspend fun addTrackToPlaylist(playlistId: Long, trackId: Long) {
        val order = (playlistDao.maxSortOrder(playlistId) ?: -1) + 1
        playlistDao.addTrack(PlaylistTrackCrossRef(playlistId, trackId, order))
    }

    suspend fun removeTrackFromPlaylist(playlistId: Long, trackId: Long) =
        playlistDao.removeTrack(playlistId, trackId)

    fun observePlaylistTracks(playlistId: Long): Flow<List<Track>> =
        playlistDao.observePlaylistTracks(playlistId).map { refs ->
            refs.mapNotNull { ref -> trackDao.getById(ref.trackId)?.toDomain() }
        }

    suspend fun getPlaylists(): List<Playlist> =
        playlistDao.getAll().map { Playlist(it.id, it.name, 0, it.createdAt) }

    // ── Downloads ─────────────────────────────────────────────────────────────
    fun observeDownloads(): Flow<List<Download>> =
        downloadDao.observeAll().map { list -> list.map { it.toDomain() } }

    // ── Metadata: manual search + re-fetch ──────────────────────────────────────
    suspend fun searchAlbumMetadata(q: String) = enricher.searchAlbumCandidates(q)
    suspend fun searchArtistMetadata(q: String) = enricher.searchArtistCandidates(q)
    suspend fun applyAlbumMetadata(albumId: Long, m: MetadataEnricher.AlbumMatch) =
        enricher.applyAlbumMatch(albumId, m)
    suspend fun applyArtistMetadata(artistId: Long, m: MetadataEnricher.ArtistMatch) =
        enricher.applyArtistMatch(artistId, m)
    suspend fun reEnrichAlbum(id: Long) = enricher.reEnrichAlbum(id)
    suspend fun reEnrichArtist(id: Long) = enricher.reEnrichArtist(id)
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
    description = description,
    secondaryArtworkUri = secondaryArtworkUri,
    label = label,
    releaseDate = releaseDate,
    manualOverride = manualOverride,
)

fun ArtistEntity.toDomain() = Artist(
    id = id,
    name = name,
    biography = biography,
    imageUri = imageUri,
    musicBrainzId = musicBrainzId,
    albumCount = 0,
    bannerUri = bannerUri,
    secondaryImageUri = secondaryImageUri,
    genre = genre,
    manualOverride = manualOverride,
)

fun DownloadEntity.toDomain() = Download(
    id = id,
    title = title,
    artist = artist,
    album = album,
    sourceUrl = sourceUrl,
    localPath = localPath,
    sizeBytes = sizeBytes,
    downloadedBytes = downloadedBytes,
    status = DownloadStatus.valueOf(status),
    dateAdded = dateAdded,
    artworkUri = artworkUri,
)
