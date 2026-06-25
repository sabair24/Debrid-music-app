package com.debridmusic.server.model

import kotlinx.serialization.Serializable

/**
 * Wire types shared with the Android (and future Apple) clients. Keep these stable —
 * the clients deserialize them verbatim.
 */

@Serializable
data class HealthDto(
    val status: String = "ok",
    val name: String = "debridmusic-server",
    val version: String,
)

@Serializable
data class TokenRequest(val username: String = "", val password: String = "")

@Serializable
data class TokenResponse(val token: String)

@Serializable
data class ArtistDto(
    val id: String,
    val name: String,
    val artworkRef: String? = null,
    val albumCount: Int = 0,
)

@Serializable
data class AlbumDto(
    val id: String,
    val artistId: String,
    val artistName: String,
    val title: String,
    val year: Int? = null,
    val artworkRef: String? = null,
    val trackCount: Int = 0,
)

@Serializable
data class TrackDto(
    val id: String,
    val albumId: String,
    val artistId: String,
    val title: String,
    val artistName: String,
    val albumTitle: String,
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
    val streamPath: String,
    val artworkRef: String? = null,
)

/** One-shot catalog used by the client's "sync now". */
@Serializable
data class CatalogDto(
    val artists: List<ArtistDto> = emptyList(),
    val albums: List<AlbumDto> = emptyList(),
    val tracks: List<TrackDto> = emptyList(),
    val generatedAt: Long = 0,
)

@Serializable
data class SearchResultDto(
    val artists: List<ArtistDto> = emptyList(),
    val albums: List<AlbumDto> = emptyList(),
    val tracks: List<TrackDto> = emptyList(),
)

@Serializable
data class IngestMetadata(
    val title: String = "",
    val artist: String = "",
    val album: String = "",
    val trackNo: Int = 0,
    val year: Int? = null,
)

@Serializable
data class IngestResponse(val trackId: String, val streamPath: String)
