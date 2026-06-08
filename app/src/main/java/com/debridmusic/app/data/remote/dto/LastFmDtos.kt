package com.debridmusic.app.data.remote.dto

import com.google.gson.annotations.SerializedName

data class LastFmArtistResponse(
    val artist: LastFmArtist? = null,
    val error: Int? = null,
    val message: String? = null,
)

data class LastFmArtist(
    val name: String = "",
    val mbid: String? = null,
    val url: String? = null,
    val image: List<LastFmImage>? = null,
    val stats: LastFmStats? = null,
    val bio: LastFmBio? = null,
    val similar: LastFmSimilar? = null,
    val tags: LastFmArtistTags? = null,
)

data class LastFmImage(
    @SerializedName("#text") val url: String = "",
    val size: String = "",
)

data class LastFmStats(
    val listeners: String? = null,
    val playcount: String? = null,
)

data class LastFmBio(
    val summary: String? = null,
    val content: String? = null,
    val published: String? = null,
)

data class LastFmSimilar(
    val artist: List<LastFmSimilarArtist>? = null,
)

data class LastFmSimilarArtist(
    val name: String = "",
    val url: String? = null,
    val image: List<LastFmImage>? = null,
)

data class LastFmArtistTags(
    val tag: List<LastFmTag>? = null,
)

data class LastFmTag(
    val name: String = "",
    val url: String? = null,
)

data class LastFmAlbumResponse(
    val album: LastFmAlbum? = null,
    val error: Int? = null,
    val message: String? = null,
)

data class LastFmAlbum(
    val name: String = "",
    val artist: String = "",
    val mbid: String? = null,
    val image: List<LastFmImage>? = null,
    val wiki: LastFmBio? = null,
    val tags: LastFmArtistTags? = null,
    val listeners: String? = null,
    val playcount: String? = null,
)
