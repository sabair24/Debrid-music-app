package com.debridmusic.app.domain.model

// Lightweight, online-metadata models for the "Stremio-style" artist browse.
// These are not persisted — they feed the browse UI and the torrent-resolve bridge.

data class BrowseArtist(
    val id: Long,
    val name: String,
    val imageUri: String?,
)

data class BrowseAlbum(
    val id: Long,
    val title: String,
    val artist: String,
    val artworkUri: String?,
    val year: Int?,
    val isSingle: Boolean,
)

data class BrowseTrack(
    val id: Long,
    val title: String,
    val artist: String,
    val album: String,
    val albumId: Long,
    val artworkUri: String?,
    val position: Int,
)

data class ArtistDiscography(
    val artist: BrowseArtist?,
    val albums: List<BrowseAlbum>,
    val singles: List<BrowseAlbum>,
    val topTracks: List<BrowseTrack>,
)
