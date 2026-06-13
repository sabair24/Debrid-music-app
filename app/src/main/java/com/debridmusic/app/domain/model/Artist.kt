package com.debridmusic.app.domain.model

data class Artist(
    val id: Long,
    val name: String,
    val biography: String?,
    val imageUri: String?,
    val musicBrainzId: String?,
    val albumCount: Int,
    val bannerUri: String? = null,
    val secondaryImageUri: String? = null,
    val genre: String? = null,
    val manualOverride: Boolean = false,
)
