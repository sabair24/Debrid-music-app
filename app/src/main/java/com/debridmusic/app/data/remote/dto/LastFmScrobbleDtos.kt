package com.debridmusic.app.data.remote.dto

import com.google.gson.annotations.SerializedName

data class LastFmSessionResponse(
    val session: LastFmSession? = null,
    val error: Int? = null,
    val message: String? = null,
)

data class LastFmSession(
    val name: String = "",
    val key: String = "",
    val subscriber: Int = 0,
)

data class LastFmScrobbleResponse(
    val scrobbles: LastFmScrobbles? = null,
    val error: Int? = null,
    val message: String? = null,
)

data class LastFmScrobbles(
    @SerializedName("@attr") val attr: LastFmScrobbleAttr? = null,
)

data class LastFmScrobbleAttr(
    val accepted: Int = 0,
    val ignored: Int = 0,
)

data class LastFmNowPlayingResponse(
    val nowplaying: LastFmNowPlaying? = null,
    val error: Int? = null,
    val message: String? = null,
)

data class LastFmNowPlaying(
    val track: LastFmCorrectedValue? = null,
    val artist: LastFmCorrectedValue? = null,
    val album: LastFmCorrectedValue? = null,
)

data class LastFmCorrectedValue(
    @SerializedName("#text") val text: String = "",
    val corrected: String = "0",
)
