package com.debridmusic.app.data.local.dao

import androidx.room.*
import com.debridmusic.app.data.local.entity.ArtistEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ArtistDao {

    @Query("SELECT * FROM artists ORDER BY name ASC")
    fun observeAll(): Flow<List<ArtistEntity>>

    @Query("SELECT * FROM artists WHERE id = :id")
    suspend fun getById(id: Long): ArtistEntity?

    @Query("SELECT * FROM artists WHERE name = :name LIMIT 1")
    suspend fun getByName(name: String): ArtistEntity?

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(artist: ArtistEntity): Long

    @Update
    suspend fun update(artist: ArtistEntity)

    @Upsert
    suspend fun upsert(artist: ArtistEntity): Long

    @Query("DELETE FROM artists WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Query("""
        SELECT a.* FROM artists a
        WHERE a.id IN (SELECT DISTINCT artistId FROM tracks WHERE artistId IS NOT NULL)
        ORDER BY a.name ASC
    """)
    fun observeArtistsWithTracks(): Flow<List<ArtistEntity>>
}
