package com.debridmusic.server.index

import com.debridmusic.server.model.AlbumDto
import com.debridmusic.server.model.ArtistDto
import com.debridmusic.server.model.SearchResultDto
import com.debridmusic.server.model.TrackDto
import java.io.File
import java.sql.Connection
import java.sql.DriverManager

/** A track as discovered on disk; also the row shape stored in SQLite. */
data class ScannedTrack(
    val id: String,
    val albumId: String,
    val artistId: String,
    val title: String,
    val artistName: String,
    val albumTitle: String,
    val trackNo: Int,
    val discNo: Int,
    val durationMs: Long,
    val bitrate: Int?,
    val sampleRate: Int?,
    val lossless: Boolean,
    val sizeBytes: Long,
    val year: Int?,
    val genre: String?,
    val mime: String?,
    val rootIndex: Int,
    val relPath: String,
) {
    fun toDto() = TrackDto(
        id = id, albumId = albumId, artistId = artistId, title = title,
        artistName = artistName, albumTitle = albumTitle, trackNo = trackNo, discNo = discNo,
        durationMs = durationMs, bitrate = bitrate, sampleRate = sampleRate, lossless = lossless,
        sizeBytes = sizeBytes, year = year, genre = genre, mime = mime,
        streamPath = "/stream/$id", artworkRef = albumId,
    )
}

/** SQLite-backed index. All access is serialized — fine for a single-user LAN server. */
class IndexStore(dbFile: File) {
    private val conn: Connection =
        DriverManager.getConnection("jdbc:sqlite:${dbFile.absolutePath}").apply {
            createStatement().use { it.execute("PRAGMA journal_mode=WAL") }
        }

    init {
        conn.createStatement().use { st ->
            st.executeUpdate(
                """CREATE TABLE IF NOT EXISTS tracks (
                    id TEXT PRIMARY KEY, album_id TEXT, artist_id TEXT, title TEXT,
                    artist_name TEXT, album_title TEXT, track_no INT, disc_no INT,
                    duration_ms INTEGER, bitrate INT, sample_rate INT, lossless INT,
                    size INTEGER, year INT, genre TEXT, mime TEXT,
                    root_index INT, rel_path TEXT, added_at INTEGER)""".trimIndent()
            )
            st.executeUpdate("CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album_id)")
            st.executeUpdate("CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist_id)")
        }
    }

    /** Atomically replaces the whole index with a fresh scan. */
    @Synchronized
    fun replaceAll(tracks: List<ScannedTrack>, generatedAt: Long) {
        conn.autoCommit = false
        try {
            conn.createStatement().use { it.executeUpdate("DELETE FROM tracks") }
            conn.prepareStatement(
                """INSERT OR REPLACE INTO tracks
                   (id,album_id,artist_id,title,artist_name,album_title,track_no,disc_no,
                    duration_ms,bitrate,sample_rate,lossless,size,year,genre,mime,root_index,rel_path,added_at)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"""
            ).use { ps ->
                for (t in tracks) {
                    ps.setString(1, t.id); ps.setString(2, t.albumId); ps.setString(3, t.artistId)
                    ps.setString(4, t.title); ps.setString(5, t.artistName); ps.setString(6, t.albumTitle)
                    ps.setInt(7, t.trackNo); ps.setInt(8, t.discNo); ps.setLong(9, t.durationMs)
                    ps.setObject(10, t.bitrate); ps.setObject(11, t.sampleRate); ps.setInt(12, if (t.lossless) 1 else 0)
                    ps.setLong(13, t.sizeBytes); ps.setObject(14, t.year); ps.setString(15, t.genre)
                    ps.setString(16, t.mime); ps.setInt(17, t.rootIndex); ps.setString(18, t.relPath)
                    ps.setLong(19, generatedAt)
                    ps.addBatch()
                }
                ps.executeBatch()
            }
            conn.commit()
        } catch (e: Exception) {
            conn.rollback(); throw e
        } finally {
            conn.autoCommit = true
        }
    }

    @Synchronized
    fun trackCount(): Int =
        conn.createStatement().use { st ->
            st.executeQuery("SELECT COUNT(*) FROM tracks").use { if (it.next()) it.getInt(1) else 0 }
        }

    @Synchronized
    fun artists(): List<ArtistDto> {
        val out = ArrayList<ArtistDto>()
        conn.createStatement().use { st ->
            st.executeQuery(
                """SELECT artist_id, artist_name,
                          COUNT(DISTINCT album_id) AS album_count, MIN(album_id) AS art
                   FROM tracks GROUP BY artist_id ORDER BY artist_name COLLATE NOCASE"""
            ).use { rs ->
                while (rs.next()) out += ArtistDto(
                    id = rs.getString("artist_id"), name = rs.getString("artist_name"),
                    artworkRef = rs.getString("art"), albumCount = rs.getInt("album_count"),
                )
            }
        }
        return out
    }

    @Synchronized
    fun albums(): List<AlbumDto> {
        val out = ArrayList<AlbumDto>()
        conn.createStatement().use { st ->
            st.executeQuery(
                """SELECT album_id, artist_id, artist_name, album_title,
                          MAX(year) AS year, COUNT(*) AS track_count
                   FROM tracks GROUP BY album_id ORDER BY album_title COLLATE NOCASE"""
            ).use { rs ->
                while (rs.next()) out += AlbumDto(
                    id = rs.getString("album_id"), artistId = rs.getString("artist_id"),
                    artistName = rs.getString("artist_name"), title = rs.getString("album_title"),
                    year = rs.getInt("year").takeIf { !rs.wasNull() },
                    artworkRef = rs.getString("album_id"), trackCount = rs.getInt("track_count"),
                )
            }
        }
        return out
    }

    @Synchronized
    fun tracks(albumId: String? = null, artistId: String? = null): List<TrackDto> {
        val where = when {
            albumId != null -> "WHERE album_id = ?"
            artistId != null -> "WHERE artist_id = ?"
            else -> ""
        }
        val out = ArrayList<TrackDto>()
        conn.prepareStatement(
            "SELECT * FROM tracks $where ORDER BY artist_name COLLATE NOCASE, album_title COLLATE NOCASE, disc_no, track_no"
        ).use { ps ->
            (albumId ?: artistId)?.let { ps.setString(1, it) }
            ps.executeQuery().use { rs -> while (rs.next()) out += rs.toScannedTrack().toDto() }
        }
        return out
    }

    @Synchronized
    fun track(id: String): ScannedTrack? =
        conn.prepareStatement("SELECT * FROM tracks WHERE id = ? LIMIT 1").use { ps ->
            ps.setString(1, id)
            ps.executeQuery().use { if (it.next()) it.toScannedTrack() else null }
        }

    /** First track of an album — used to resolve the album cover. */
    @Synchronized
    fun firstTrackOfAlbum(albumId: String): ScannedTrack? =
        conn.prepareStatement(
            "SELECT * FROM tracks WHERE album_id = ? ORDER BY disc_no, track_no LIMIT 1"
        ).use { ps ->
            ps.setString(1, albumId)
            ps.executeQuery().use { if (it.next()) it.toScannedTrack() else null }
        }

    @Synchronized
    fun search(q: String): SearchResultDto {
        val like = "%${q.lowercase()}%"
        val artists = ArrayList<ArtistDto>()
        val albums = ArrayList<AlbumDto>()
        val tracks = ArrayList<TrackDto>()
        conn.prepareStatement(
            "SELECT DISTINCT artist_id, artist_name FROM tracks WHERE LOWER(artist_name) LIKE ? ORDER BY artist_name LIMIT 50"
        ).use { ps -> ps.setString(1, like); ps.executeQuery().use { rs ->
            while (rs.next()) artists += ArtistDto(rs.getString(1), rs.getString(2), rs.getString(1))
        } }
        conn.prepareStatement(
            "SELECT album_id, artist_id, artist_name, album_title FROM tracks WHERE LOWER(album_title) LIKE ? GROUP BY album_id ORDER BY album_title LIMIT 50"
        ).use { ps -> ps.setString(1, like); ps.executeQuery().use { rs ->
            while (rs.next()) albums += AlbumDto(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), artworkRef = rs.getString(1))
        } }
        conn.prepareStatement(
            "SELECT * FROM tracks WHERE LOWER(title) LIKE ? ORDER BY title LIMIT 100"
        ).use { ps -> ps.setString(1, like); ps.executeQuery().use { rs ->
            while (rs.next()) tracks += rs.toScannedTrack().toDto()
        } }
        return SearchResultDto(artists, albums, tracks)
    }

    private fun java.sql.ResultSet.toScannedTrack() = ScannedTrack(
        id = getString("id"), albumId = getString("album_id"), artistId = getString("artist_id"),
        title = getString("title"), artistName = getString("artist_name"), albumTitle = getString("album_title"),
        trackNo = getInt("track_no"), discNo = getInt("disc_no"), durationMs = getLong("duration_ms"),
        bitrate = getInt("bitrate").takeIf { !wasNull() }, sampleRate = getInt("sample_rate").takeIf { !wasNull() },
        lossless = getInt("lossless") == 1, sizeBytes = getLong("size"),
        year = getInt("year").takeIf { !wasNull() }, genre = getString("genre"), mime = getString("mime"),
        rootIndex = getInt("root_index"), relPath = getString("rel_path"),
    )
}
