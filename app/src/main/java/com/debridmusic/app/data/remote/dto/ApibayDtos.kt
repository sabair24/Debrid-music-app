package com.debridmusic.app.data.remote.dto

import com.google.gson.annotations.SerializedName

// apibay returns numeric fields as JSON strings.
data class ApibayResult(
    val id: String? = null,
    val name: String? = null,
    @SerializedName("info_hash") val infoHash: String? = null,
    val seeders: String? = null,
    val leechers: String? = null,
    val size: String? = null, // bytes, as string
    @SerializedName("num_files") val numFiles: String? = null,
    val category: String? = null,
) {
    // apibay returns a single sentinel row with this hash when there are no results.
    val isNoResults: Boolean
        get() = infoHash == null || infoHash == "0000000000000000000000000000000000000000" ||
            name == "No results returned"
}
