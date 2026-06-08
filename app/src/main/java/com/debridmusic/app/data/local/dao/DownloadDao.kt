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

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(download: DownloadEntity): Long

    @Update
    suspend fun update(download: DownloadEntity)

    @Query("DELETE FROM downloads WHERE id = :id")
    suspend fun deleteById(id: Long)
}
