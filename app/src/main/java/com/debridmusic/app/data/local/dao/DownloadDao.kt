package com.debridmusic.app.data.local.dao

import androidx.room.*
import com.debridmusic.app.data.local.entity.DownloadEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface DownloadDao {

    @Query("SELECT * FROM downloads ORDER BY dateAdded DESC")
    fun observeAll(): Flow<List<DownloadEntity>>

    @Query("SELECT * FROM downloads WHERE id = :id")
    suspend fun getById(id: Long): DownloadEntity?

    @Query("SELECT * FROM downloads WHERE sourceUrl = :url LIMIT 1")
    suspend fun getByUrl(url: String): DownloadEntity?

    @Query("SELECT * FROM downloads WHERE status = 'DONE' AND localPath != ''")
    suspend fun getCompleted(): List<DownloadEntity>

    @Query("SELECT COALESCE(SUM(sizeBytes), 0) FROM downloads WHERE status = 'DONE'")
    suspend fun completedSizeBytes(): Long

    @Query("SELECT * FROM downloads WHERE status = 'QUEUED' ORDER BY dateAdded ASC LIMIT 1")
    suspend fun nextQueued(): DownloadEntity?

    @Query("SELECT * FROM downloads WHERE status = 'DONE' AND localPath != '' ORDER BY dateAdded ASC")
    suspend fun getCompletedOldestFirst(): List<DownloadEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(download: DownloadEntity): Long

    @Update
    suspend fun update(download: DownloadEntity)

    @Query("DELETE FROM downloads WHERE id = :id")
    suspend fun deleteById(id: Long)
}
