package com.debridmusic.app.data.local.dao

import androidx.room.*
import com.debridmusic.app.data.local.entity.AlbumEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface AlbumDao {

    @Query("SELECT * FROM albums ORDER BY title ASC")
    fun observeAll(): Flow<List<AlbumEntity>>

    @Query("SELECT * FROM albums WHERE artistId = :artistId ORDER BY year ASC, title ASC")
    fun observeByArtist(artistId: Long): Flow<List<AlbumEntity>>

    @Query("SELECT * FROM albums WHERE id = :id")
    suspend fun getById(id: Long): AlbumEntity?

    @Query("SELECT * FROM albums WHERE title = :title AND artistId = :artistId LIMIT 1")
    suspend fun getByTitleAndArtist(title: String, artistId: Long): AlbumEntity?

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(album: AlbumEntity): Long

    @Update
    suspend fun update(album: AlbumEntity)

    @Upsert
    suspend fun upsert(album: AlbumEntity): Long

    @Query("DELETE FROM albums WHERE id = :id")
    suspend fun deleteById(id: Long)

    /** Removes orphan albums that have no tracks (e.g. left over after a re-tag). */
    @Query("DELETE FROM albums WHERE id NOT IN (SELECT DISTINCT albumId FROM tracks)")
    suspend fun deleteEmpty(): Int

    @Query("""
        SELECT al.*, COUNT(t.id) as trackCount
        FROM albums al
        LEFT JOIN tracks t ON t.albumId = al.id
        GROUP BY al.id
        HAVING COUNT(t.id) > 0
        ORDER BY al.title ASC
    """)
    fun observeAlbumsWithTrackCount(): Flow<List<AlbumWithCount>>
}

data class AlbumWithCount(
    val id: Long,
    val title: String,
    val artistId: Long,
    val artistName: String,
    val year: Int?,
    val artworkUri: String?,
    val genre: String?,
    val musicBrainzId: String?,
    val recordType: String? = null,
    val trackCount: Int,
)
