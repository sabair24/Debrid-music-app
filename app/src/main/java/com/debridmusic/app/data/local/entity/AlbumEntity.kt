package com.debridmusic.app.data.local.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "albums",
    foreignKeys = [
        ForeignKey(
            entity = ArtistEntity::class,
            parentColumns = ["id"],
            childColumns = ["artistId"],
            onDelete = ForeignKey.CASCADE,
        )
    ],
    indices = [Index("artistId")]
)
data class AlbumEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val title: String,
    val artistId: Long,
    val artistName: String,
    val year: Int? = null,
    val artworkUri: String? = null,
    val genre: String? = null,
    val musicBrainzId: String? = null,
)
