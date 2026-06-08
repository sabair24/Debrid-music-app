package com.debridmusic.app.data.local.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "tracks",
    foreignKeys = [
        ForeignKey(
            entity = AlbumEntity::class,
            parentColumns = ["id"],
            childColumns = ["albumId"],
            onDelete = ForeignKey.SET_NULL,
        ),
        ForeignKey(
            entity = ArtistEntity::class,
            parentColumns = ["id"],
            childColumns = ["artistId"],
            onDelete = ForeignKey.SET_NULL,
        ),
    ],
    indices = [Index("albumId"), Index("artistId"), Index("uri", unique = true)]
)
data class TrackEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val title: String,
    val artistName: String,
    val albumTitle: String,
    val albumId: Long?,
    val artistId: Long?,
    val uri: String,
    val durationMs: Long,
    val trackNumber: Int = 0,
    val discNumber: Int = 1,
    val year: Int? = null,
    val artworkUri: String? = null,
    val genre: String? = null,
    val bitrate: Int? = null,
    val sampleRate: Int? = null,
    val isLossless: Boolean = false,
    val fileSize: Long = 0,
    val dateAdded: Long = System.currentTimeMillis(),
)
