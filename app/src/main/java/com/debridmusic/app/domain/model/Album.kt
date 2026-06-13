package com.debridmusic.app.domain.model

data class Album(
    val id: Long,
    val title: String,
    val artistName: String,
    val artistId: Long,
    val year: Int?,
    val artworkUri: String?,
    val trackCount: Int,
    val genre: String?,
    val musicBrainzId: String?,
    val description: String? = null,
    val secondaryArtworkUri: String? = null,
    val label: String? = null,
    val releaseDate: String? = null,
    val manualOverride: Boolean = false,
)
