package com.debridmusic.app.data.local.dao

import androidx.room.*
import com.debridmusic.app.data.local.entity.PlaylistEntity
import com.debridmusic.app.data.local.entity.PlaylistTrackCrossRef
import kotlinx.coroutines.flow.Flow

data class PlaylistWithTrackCount(
    val id: Long,
    val name: String,
    val createdAt: Long,
    val trackCount: Int,
)

@Dao
interface PlaylistDao {

    @Query("SELECT p.id, p.name, p.createdAt, COUNT(c.trackId) AS trackCount FROM playlists p LEFT JOIN playlist_track_cross_ref c ON p.id = c.playlistId GROUP BY p.id ORDER BY p.createdAt DESC")
    fun observeAllWithCount(): Flow<List<PlaylistWithTrackCount>>

    @Query("SELECT * FROM playlists WHERE id = :id")
    suspend fun getById(id: Long): PlaylistEntity?

    @Query("SELECT * FROM playlists ORDER BY name ASC")
    suspend fun getAll(): List<PlaylistEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(playlist: PlaylistEntity): Long

    @Query("DELETE FROM playlists WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun addTrack(crossRef: PlaylistTrackCrossRef)

    @Query("DELETE FROM playlist_track_cross_ref WHERE playlistId = :playlistId AND trackId = :trackId")
    suspend fun removeTrack(playlistId: Long, trackId: Long)

    @Query("SELECT * FROM playlist_track_cross_ref WHERE playlistId = :playlistId ORDER BY sortOrder ASC")
    fun observePlaylistTracks(playlistId: Long): Flow<List<PlaylistTrackCrossRef>>

    @Query("SELECT COUNT(*) FROM playlist_track_cross_ref WHERE playlistId = :playlistId AND trackId = :trackId")
    suspend fun containsTrack(playlistId: Long, trackId: Long): Int

    @Query("SELECT MAX(sortOrder) FROM playlist_track_cross_ref WHERE playlistId = :playlistId")
    suspend fun maxSortOrder(playlistId: Long): Int?
}
