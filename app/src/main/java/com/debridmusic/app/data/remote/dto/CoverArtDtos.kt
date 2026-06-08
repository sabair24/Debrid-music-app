package com.debridmusic.app.data.remote.dto

import com.google.gson.annotations.SerializedName

data class CoverArtResponse(
    val images: List<CoverArtImage>? = null,
    val release: String? = null,
)

data class CoverArtImage(
    val image: String? = null,
    val thumbnails: CoverArtThumbnails? = null,
    val front: Boolean = false,
    val back: Boolean = false,
    val approved: Boolean = false,
)

data class CoverArtThumbnails(
    val small: String? = null,
    val large: String? = null,
    @SerializedName("250") val p250: String? = null,
    @SerializedName("500") val p500: String? = null,
    @SerializedName("1200") val p1200: String? = null,
)

fun CoverArtResponse.bestFrontUrl(): String? {
    val front = images?.firstOrNull { it.front && it.approved }
        ?: images?.firstOrNull { it.front }
        ?: images?.firstOrNull()
    return front?.thumbnails?.p500
        ?: front?.thumbnails?.large
        ?: front?.thumbnails?.p250
        ?: front?.image
}
