package com.debridmusic.app.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "artists",
    indices = [Index(value = ["name"], unique = true)]
)
data class ArtistEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val biography: String? = null,
    val imageUri: String? = null,
    val musicBrainzId: String? = null,
    // Rich metadata (enrichment)
    val bannerUri: String? = null,              // wide fan art
    val secondaryImageUri: String? = null,
    val genre: String? = null,
    val deezerId: Long? = null,
    val theAudioDbId: String? = null,
    val manualOverride: Boolean = false,
)
