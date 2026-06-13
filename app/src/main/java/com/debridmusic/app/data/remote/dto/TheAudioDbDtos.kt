package com.debridmusic.app.data.remote.dto

import com.google.gson.annotations.SerializedName

// TheAudioDB free JSON API (public key in base URL). Source for artist
// biographies, fan-art banners, album descriptions and art.
// Note: wrapper is `artists` (plural) for artist queries, `album` (singular)
// for album queries; null (not []) on no match; numeric fields are strings.

data class TadbArtistResponse(val artists: List<TadbArtist>? = null)
data class TadbAlbumResponse(val album: List<TadbAlbum>? = null)

data class TadbArtist(
    @SerializedName("idArtist") val idArtist: String? = null,
    @SerializedName("strArtist") val strArtist: String? = null,
    @SerializedName(value = "strBiographyEN", alternate = ["strBiography"]) val biography: String? = null,
    @SerializedName("strGenre") val genre: String? = null,
    @SerializedName("strStyle") val style: String? = null,
    @SerializedName("strArtistThumb") val thumb: String? = null,
    @SerializedName("strArtistFanart") val fanart: String? = null,
    @SerializedName("strArtistBanner") val banner: String? = null,
    @SerializedName("strArtistWideThumb") val wideThumb: String? = null,
    @SerializedName("strMusicBrainzID") val mbid: String? = null,
)

data class TadbAlbum(
    @SerializedName("idAlbum") val idAlbum: String? = null,
    @SerializedName("strAlbum") val strAlbum: String? = null,
    @SerializedName("intYearReleased") val year: String? = null,
    @SerializedName("strGenre") val genre: String? = null,
    @SerializedName("strLabel") val label: String? = null,
    @SerializedName(value = "strDescriptionEN", alternate = ["strDescription"]) val description: String? = null,
    @SerializedName("strAlbumThumb") val thumb: String? = null,
    @SerializedName("strAlbumThumbHQ") val thumbHq: String? = null,
    @SerializedName("strAlbumBack") val back: String? = null,
    @SerializedName("strMusicBrainzID") val mbid: String? = null,
)
