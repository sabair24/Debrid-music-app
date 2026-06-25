package com.debridmusic.app.server

/** Wire types from the music server (Gson; field names match the server's JSON). */

data class ServerHealthDto(
    val status: String = "",
    val name: String = "",
    val version: String = "",
)

data class ServerArtistDto(
    val id: String = "",
    val name: String = "",
    val artworkRef: String? = null,
    val albumCount: Int = 0,
)

data class ServerAlbumDto(
    val id: String = "",
    val artistId: String = "",
    val artistName: String = "",
    val title: String = "",
    val year: Int? = null,
    val artworkRef: String? = null,
    val trackCount: Int = 0,
)

data class ServerTrackDto(
    val id: String = "",
    val albumId: String = "",
    val artistId: String = "",
    val title: String = "",
    val artistName: String = "",
    val albumTitle: String = "",
    val trackNo: Int = 0,
    val discNo: Int = 1,
    val durationMs: Long = 0,
    val bitrate: Int? = null,
    val sampleRate: Int? = null,
    val lossless: Boolean = false,
    val sizeBytes: Long = 0,
    val year: Int? = null,
    val genre: String? = null,
    val mime: String? = null,
    val streamPath: String = "",
    val artworkRef: String? = null,
)

data class ServerCatalogDto(
    val artists: List<ServerArtistDto> = emptyList(),
    val albums: List<ServerAlbumDto> = emptyList(),
    val tracks: List<ServerTrackDto> = emptyList(),
    val generatedAt: Long = 0,
)

data class ServerIngestResponse(
    val trackId: String = "",
    val streamPath: String = "",
)
