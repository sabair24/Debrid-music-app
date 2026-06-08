package com.debridmusic.app.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.debridmusic.app.data.local.dao.AlbumDao
import com.debridmusic.app.data.local.dao.ArtistDao
import com.debridmusic.app.data.local.dao.DownloadDao
import com.debridmusic.app.data.local.dao.PlaylistDao
import com.debridmusic.app.data.local.dao.TrackDao
import com.debridmusic.app.data.local.entity.AlbumEntity
import com.debridmusic.app.data.local.entity.ArtistEntity
import com.debridmusic.app.data.local.entity.DownloadEntity
import com.debridmusic.app.data.local.entity.PlaylistEntity
import com.debridmusic.app.data.local.entity.PlaylistTrackCrossRef
import com.debridmusic.app.data.local.entity.TrackEntity

@Database(
    entities = [
        TrackEntity::class,
        AlbumEntity::class,
        ArtistEntity::class,
        PlaylistEntity::class,
        PlaylistTrackCrossRef::class,
        DownloadEntity::class,
    ],
    version = 2,
    exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun trackDao(): TrackDao
    abstract fun albumDao(): AlbumDao
    abstract fun artistDao(): ArtistDao
    abstract fun playlistDao(): PlaylistDao
    abstract fun downloadDao(): DownloadDao

    companion object {
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS playlists " +
                            "(id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                            "name TEXT NOT NULL, " +
                            "createdAt INTEGER NOT NULL)"
                )
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS playlist_track_cross_ref " +
                            "(playlistId INTEGER NOT NULL, " +
                            "trackId INTEGER NOT NULL, " +
                            "sortOrder INTEGER NOT NULL, " +
                            "PRIMARY KEY(playlistId, trackId), " +
                            "FOREIGN KEY(playlistId) REFERENCES playlists(id) ON DELETE CASCADE)"
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS index_ptcr_trackId ON playlist_track_cross_ref(trackId)")
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS downloads " +
                            "(id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                            "title TEXT NOT NULL, " +
                            "artist TEXT NOT NULL, " +
                            "album TEXT NOT NULL, " +
                            "sourceUrl TEXT NOT NULL, " +
                            "localPath TEXT NOT NULL DEFAULT '', " +
                            "sizeBytes INTEGER NOT NULL DEFAULT 0, " +
                            "downloadedBytes INTEGER NOT NULL DEFAULT 0, " +
                            "status TEXT NOT NULL DEFAULT 'QUEUED', " +
                            "dateAdded INTEGER NOT NULL)"
                )
            }
        }
    }
}
