package com.debridmusic.app.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import com.debridmusic.app.data.local.dao.AlbumDao
import com.debridmusic.app.data.local.dao.ArtistDao
import com.debridmusic.app.data.local.dao.TrackDao
import com.debridmusic.app.data.local.entity.AlbumEntity
import com.debridmusic.app.data.local.entity.ArtistEntity
import com.debridmusic.app.data.local.entity.TrackEntity

@Database(
    entities = [TrackEntity::class, AlbumEntity::class, ArtistEntity::class],
    version = 1,
    exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun trackDao(): TrackDao
    abstract fun albumDao(): AlbumDao
    abstract fun artistDao(): ArtistDao
}
