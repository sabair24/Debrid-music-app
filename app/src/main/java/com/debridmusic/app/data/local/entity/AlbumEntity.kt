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
    // Rich metadata (enrichment)
    val description: String? = null,
    val secondaryArtworkUri: String? = null,   // back cover
    val label: String? = null,
    val releaseDate: String? = null,            // ISO yyyy-MM-dd
    val deezerId: Long? = null,
    val theAudioDbId: String? = null,
    val recordType: String? = null,            // Deezer record_type: album / single / ep
    val manualOverride: Boolean = false,        // user picked this match → don't auto-overwrite
)
