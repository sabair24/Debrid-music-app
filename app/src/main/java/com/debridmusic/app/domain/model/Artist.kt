package com.debridmusic.app.domain.model

data class Artist(
    val id: Long,
    val name: String,
    val biography: String?,
    val imageUri: String?,
    val musicBrainzId: String?,
    val albumCount: Int,
)
