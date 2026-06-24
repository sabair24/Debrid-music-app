package com.debridmusic.app.data.remote.dto

import com.google.gson.annotations.SerializedName

// Deezer public API — no key/OAuth required. Great keyless source for artist
// images and album covers (4 sizes, near-universal).

data class DeezerSearchResponse<T>(
    val data: List<T>? = null,
    val total: Int? = null,
    val next: String? = null,
    val error: DeezerError? = null,
)

data class DeezerError(val type: String? = null, val message: String? = null, val code: Int? = null)

data class DeezerArtist(
    val id: Long = 0,
    val name: String? = null,
    val link: String? = null,
    val picture: String? = null,
    @SerializedName("picture_small") val pictureSmall: String? = null,
    @SerializedName("picture_medium") val pictureMedium: String? = null,
    @SerializedName("picture_big") val pictureBig: String? = null,
    @SerializedName("picture_xl") val pictureXl: String? = null,
    @SerializedName("nb_album") val nbAlbum: Int? = null,
    @SerializedName("nb_fan") val nbFan: Int? = null,
)

data class DeezerAlbum(
    val id: Long = 0,
    val title: String? = null,
    val link: String? = null,
    val label: String? = null,
    val cover: String? = null,
    @SerializedName("cover_small") val coverSmall: String? = null,
    @SerializedName("cover_medium") val coverMedium: String? = null,
    @SerializedName("cover_big") val coverBig: String? = null,
    @SerializedName("cover_xl") val coverXl: String? = null,
    @SerializedName("nb_tracks") val nbTracks: Int? = null,
    @SerializedName("release_date") val releaseDate: String? = null, // yyyy-MM-dd
    @SerializedName("record_type") val recordType: String? = null,
    val genres: DeezerGenresWrapper? = null,
    val artist: DeezerArtist? = null,
)

data class DeezerGenresWrapper(val data: List<DeezerGenre>? = null)
data class DeezerGenre(val id: Int? = null, val name: String? = null)

data class DeezerTrack(
    val id: Long = 0,
    val title: String? = null,
    val duration: Int? = null,                                   // seconds
    @SerializedName("track_position") val trackPosition: Int? = null,
    @SerializedName("disk_number") val diskNumber: Int? = null,
    val artist: DeezerArtist? = null,
    val album: DeezerAlbum? = null,
)

fun DeezerArtist.bestImage(): String? =
    listOf(pictureXl, pictureBig, pictureMedium, picture).firstOrNull { !it.isNullOrBlank() }

fun DeezerAlbum.bestCover(): String? =
    listOf(coverXl, coverBig, coverMedium, cover).firstOrNull { !it.isNullOrBlank() }

fun DeezerAlbum.genreName(): String? = genres?.data?.firstOrNull()?.name
