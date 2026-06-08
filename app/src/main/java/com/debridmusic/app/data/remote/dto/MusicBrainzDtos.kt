package com.debridmusic.app.data.remote.dto

import com.google.gson.annotations.SerializedName

data class MbReleaseSearchResult(
    val releases: List<MbRelease>? = null,
    val count: Int? = null,
)

data class MbRelease(
    val id: String = "",
    val title: String = "",
    val date: String? = null,
    val status: String? = null,
    @SerializedName("artist-credit") val artistCredit: List<MbArtistCredit>? = null,
    @SerializedName("release-group") val releaseGroup: MbReleaseGroup? = null,
    val media: List<MbMedium>? = null,
    val score: Int? = null,
)

data class MbArtistCredit(
    val name: String? = null,
    val artist: MbArtist? = null,
)

data class MbArtist(
    val id: String = "",
    val name: String = "",
    @SerializedName("sort-name") val sortName: String? = null,
    val disambiguation: String? = null,
)

data class MbReleaseGroup(
    val id: String = "",
    @SerializedName("primary-type") val primaryType: String? = null,
)

data class MbMedium(
    val position: Int? = null,
    val format: String? = null,
    @SerializedName("track-count") val trackCount: Int? = null,
)

data class MbArtistSearchResult(
    val artists: List<MbArtistDetail>? = null,
    val count: Int? = null,
)

data class MbArtistDetail(
    val id: String = "",
    val name: String = "",
    @SerializedName("sort-name") val sortName: String? = null,
    val disambiguation: String? = null,
    val country: String? = null,
    val score: Int? = null,
    val tags: List<MbTag>? = null,
)

data class MbTag(
    val name: String = "",
    val count: Int? = null,
)
