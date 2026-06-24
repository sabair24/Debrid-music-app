package com.debridmusic.app.data.remote.dto

import com.google.gson.annotations.SerializedName

// Discogs API (api.discogs.com). Requires the user's personal access token, sent
// as an "Authorization: Discogs token=…" header. Rich release/artist metadata and
// high-quality cover art; complements the keyless Deezer/MusicBrainz sources.

data class DiscogsSearchResponse(
    val results: List<DiscogsSearchResult>? = null,
)

data class DiscogsSearchResult(
    val id: Long = 0,
    val type: String? = null,                 // "release", "master", "artist"
    val title: String? = null,                // "Artist - Album" for releases; artist name for artists
    val year: String? = null,
    val genre: List<String>? = null,
    val style: List<String>? = null,
    val label: List<String>? = null,
    val thumb: String? = null,
    @SerializedName("cover_image") val coverImage: String? = null,
    @SerializedName("master_id") val masterId: Long? = null,
)

data class DiscogsRelease(
    val id: Long = 0,
    val title: String? = null,
    val year: Int? = null,
    val released: String? = null,             // ISO yyyy-MM-dd (may be just yyyy)
    val genres: List<String>? = null,
    val styles: List<String>? = null,
    val labels: List<DiscogsLabel>? = null,
    val images: List<DiscogsImage>? = null,
    val tracklist: List<DiscogsTrack>? = null,
    val formats: List<DiscogsFormat>? = null,
)

data class DiscogsFormat(
    val name: String? = null,                 // "Vinyl", "CD", "File", …
    val descriptions: List<String>? = null,   // e.g. ["Single", "Maxi-Single"], ["EP"], ["Album", "LP"]
)

data class DiscogsTrack(
    val position: String? = null,             // "A1", "1", … (vinyl side or index)
    @SerializedName("type_") val type: String? = null,   // "track" | "heading" | "index"
    val title: String? = null,
    val duration: String? = null,
)

data class DiscogsLabel(val name: String? = null)

data class DiscogsImage(
    val type: String? = null,                 // "primary" | "secondary"
    val uri: String? = null,
    val uri150: String? = null,
    @SerializedName("resource_url") val resourceUrl: String? = null,
)

data class DiscogsArtistDetail(
    val id: Long = 0,
    val name: String? = null,
    val profile: String? = null,
    val images: List<DiscogsImage>? = null,
)

// Returned by GET /oauth/identity — used to verify the user's token.
data class DiscogsIdentity(
    val id: Long = 0,
    val username: String? = null,
    @SerializedName("resource_url") val resourceUrl: String? = null,
)

// ── User collection ──────────────────────────────────────────────────────────

data class DiscogsCollectionResponse(
    val pagination: DiscogsPagination? = null,
    val releases: List<DiscogsCollectionRelease>? = null,
)

data class DiscogsPagination(val page: Int = 1, val pages: Int = 1, val items: Int = 0)

data class DiscogsCollectionRelease(
    @SerializedName("basic_information") val basicInformation: DiscogsBasicInformation? = null,
)

data class DiscogsBasicInformation(
    val id: Long = 0,                          // release id
    val title: String? = null,
    val year: Int? = null,
    @SerializedName("cover_image") val coverImage: String? = null,
    val thumb: String? = null,
    val artists: List<DiscogsCollectionArtist>? = null,
)

data class DiscogsCollectionArtist(val name: String? = null)

// Flat, persisted (DataStore JSON) representation of one collection album.
data class DiscogsCollectionAlbum(
    val releaseId: Long,
    val title: String,
    val artist: String,
    val artworkUri: String?,
    val year: Int?,
)

// Discogs disambiguates same-named artists with a trailing " (2)"; drop it for display.
fun String.cleanDiscogsArtist(): String =
    replace(Regex("\\s*\\(\\d+\\)\\s*$"), "").trim()

// ── Helpers ──────────────────────────────────────────────────────────────────

fun DiscogsSearchResult.bestImage(): String? =
    listOf(coverImage, thumb).firstOrNull { !it.isNullOrBlank() }

fun DiscogsImage.bestUri(): String? = uri?.takeIf { it.isNotBlank() } ?: uri150

fun DiscogsRelease.primaryImage(): String? =
    (images?.firstOrNull { it.type == "primary" } ?: images?.firstOrNull())?.bestUri()

fun DiscogsRelease.secondaryImage(): String? =
    images?.firstOrNull { it.type == "secondary" }?.bestUri()

fun DiscogsRelease.genreName(): String? =
    (genres?.firstOrNull { it.isNotBlank() } ?: styles?.firstOrNull { it.isNotBlank() })

fun DiscogsRelease.labelName(): String? = labels?.firstOrNull { !it.name.isNullOrBlank() }?.name

// Maps Discogs format descriptions to a Deezer-style record type (single / ep / album).
fun DiscogsRelease.recordType(): String? {
    val descs = formats?.flatMap { it.descriptions.orEmpty() }.orEmpty()
    return when {
        descs.any { it.contains("Single", ignoreCase = true) } -> "single"
        descs.any { it.equals("EP", ignoreCase = true) } -> "ep"
        descs.any { it.contains("Album", ignoreCase = true) || it.contains("LP", ignoreCase = true) } -> "album"
        else -> null
    }
}

fun DiscogsArtistDetail.bestImage(): String? = images?.firstNotNullOfOrNull { it.bestUri() }

// Discogs profiles use BBCode-style markup ([a=Name], [b], [url=…]text[/url], …).
// Strip the bracket tags and collapse whitespace for a clean bio string.
fun String.stripDiscogsMarkup(): String =
    replace(Regex("\\[/?[abilru](=[^\\]]*)?\\]", RegexOption.IGNORE_CASE), "")
        .replace(Regex("\\[[^\\]]*\\]"), "")
        .replace(Regex("\\s+"), " ").trim()
