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

data class ServerSearchDto(
    val artists: List<ServerArtistDto> = emptyList(),
    val albums: List<ServerAlbumDto> = emptyList(),
    val tracks: List<ServerTrackDto> = emptyList(),
)

// ── Pairing ──────────────────────────────────────────────────────────────────

data class ServerPairRequest(val code: String, val device: String)

data class ServerPairResponse(
    val token: String = "",
    val name: String = "",
    val trackCount: Int = 0,
)

// ── Shared state ─────────────────────────────────────────────────────────────

/**
 * Playlists, favourites, play position and counts, as the PC holds them.
 *
 * Two revisions on purpose. [rev] covers what changes rarely and is worth re-fetching for;
 * [progressRev] covers the play position, which moves several times a second — sharing one
 * counter would have every device re-pulling the whole state for the length of every track.
 */
data class ServerStateDto(
    val rev: Long = 0,
    val progressRev: Long = 0,
    val unchanged: Boolean = false,
    val favoriteTracks: List<String> = emptyList(),
    val favoriteAlbums: List<String> = emptyList(),
    val playlists: List<ServerPlaylistDto> = emptyList(),
    val plays: Map<String, ServerPlayStatDto> = emptyMap(),
    val progress: ServerProgressDto? = null,
)

data class ServerPlaylistDto(
    val id: String = "",
    val name: String = "",
    val trackIds: List<String> = emptyList(),
    val updatedAt: Long = 0,
    /** Non-null means deleted elsewhere; the entry is a tombstone, not a playlist. */
    val deletedAt: Long? = null,
)

data class ServerPlayStatDto(
    val count: Int = 0,
    val lastPlayedMs: Long = 0,
)

data class ServerProgressDto(
    val trackId: String = "",
    val positionMs: Long = 0,
    val queue: List<String> = emptyList(),
    val index: Int = 0,
    val playing: Boolean = false,
    val updatedAt: Long = 0,
    val deviceId: String = "",
    val deviceName: String = "",
)

/** A batch of changes this device made, on their way to the PC. */
data class ServerOpsRequest(
    val deviceId: String,
    val deviceName: String,
    val ops: List<Map<String, Any?>>,
)

data class ServerOpsResponse(
    val rev: Long = 0,
    val progressRev: Long = 0,
)
