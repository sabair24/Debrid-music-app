package com.debridmusic.app.data.local.dao

import androidx.room.*
import com.debridmusic.app.data.local.entity.TrackEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface TrackDao {

    @Query("SELECT * FROM tracks ORDER BY artistName ASC, albumTitle ASC, discNumber ASC, trackNumber ASC")
    fun observeAll(): Flow<List<TrackEntity>>

    @Query("SELECT * FROM tracks WHERE albumId = :albumId ORDER BY discNumber ASC, trackNumber ASC")
    fun observeByAlbum(albumId: Long): Flow<List<TrackEntity>>

    @Query("SELECT * FROM tracks WHERE artistId = :artistId ORDER BY albumTitle ASC, discNumber ASC, trackNumber ASC")
    fun observeByArtist(artistId: Long): Flow<List<TrackEntity>>

    @Query("SELECT * FROM tracks WHERE id = :id")
    suspend fun getById(id: Long): TrackEntity?

    @Query("SELECT * FROM tracks WHERE uri = :uri LIMIT 1")
    suspend fun getByUri(uri: String): TrackEntity?

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(track: TrackEntity): Long

    @Upsert
    suspend fun upsert(track: TrackEntity): Long

    @Update
    suspend fun update(track: TrackEntity)

    @Query("DELETE FROM tracks WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Query("DELETE FROM tracks WHERE uri = :uri")
    suspend fun deleteByUri(uri: String)

    @Query("""
        SELECT * FROM tracks
        WHERE title LIKE '%' || :query || '%'
           OR artistName LIKE '%' || :query || '%'
           OR albumTitle LIKE '%' || :query || '%'
        ORDER BY title ASC
        LIMIT 50
    """)
    suspend fun search(query: String): List<TrackEntity>

    @Query("SELECT COUNT(*) FROM tracks")
    fun countAll(): Flow<Int>

    @Query("SELECT * FROM tracks ORDER BY dateAdded DESC LIMIT :limit")
    fun observeRecentlyAdded(limit: Int = 20): Flow<List<TrackEntity>>
}
