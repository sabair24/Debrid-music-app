package com.debridmusic.server.search

import com.debridmusic.server.net.Http
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.net.URLEncoder

private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

// ── Pirate Bay via apibay.org ────────────────────────────────────────────────
@Serializable
private data class ApibayResult(
    val name: String? = null,
    @SerialName("info_hash") val infoHash: String? = null,
    val seeders: String? = null,
    val leechers: String? = null,
    val size: String? = null,
    val category: String? = null,
) {
    val isNoResults: Boolean
        get() = infoHash == null || infoHash == "0".repeat(40) || name == "No results returned"
}

class ApibaySource : SearchSource {
    override val id = "apibay"
    override fun isEnabled() = true
    override suspend fun search(query: String): List<SearchResult> = withContext(Dispatchers.IO) {
        val resp = Http.get("https://apibay.org/q.php?q=${enc(query)}&cat=100")
        if (!resp.ok) return@withContext emptyList()
        val arr = runCatching { Http.json.decodeFromString<List<ApibayResult>>(resp.body) }.getOrDefault(emptyList())
        arr.asSequence()
            .filter { !it.isNoResults && (it.category?.toIntOrNull() ?: 0) in 100..199 }
            .mapNotNull { r ->
                val hash = r.infoHash?.lowercase() ?: return@mapNotNull null
                SearchResult(
                    name = r.name.orEmpty(), size = r.size?.toLongOrNull() ?: 0,
                    seeders = r.seeders?.toIntOrNull() ?: 0, leechers = r.leechers?.toIntOrNull() ?: 0,
                    hash = hash, magnet = magnetFor(hash, r.name.orEmpty()), source = "Pirate Bay",
                )
            }.toList()
    }
}

// ── BitSearch ────────────────────────────────────────────────────────────────
@Serializable
private data class BitSearchResponse(val success: Boolean = false, val results: List<BitSearchResult>? = null)

@Serializable
private data class BitSearchResult(
    val infohash: String = "", val title: String = "", val size: Long = 0,
    val seeders: Int = 0, val leechers: Int = 0,
)

class BitSearchSource : SearchSource {
    override val id = "bitsearch"
    override fun isEnabled() = true
    override suspend fun search(query: String): List<SearchResult> = withContext(Dispatchers.IO) {
        val resp = Http.get("https://bitsearch.eu/api/v1/search?q=${enc(query)}&category=audio&sort=seeders&p=1")
        if (!resp.ok) return@withContext emptyList()
        val body = runCatching { Http.json.decodeFromString<BitSearchResponse>(resp.body) }.getOrNull() ?: return@withContext emptyList()
        if (!body.success) return@withContext emptyList()
        body.results.orEmpty().filter { it.infohash.isNotBlank() }.map { r ->
            SearchResult(
                name = r.title, size = r.size, seeders = r.seeders, leechers = r.leechers,
                hash = r.infohash.lowercase(), magnet = magnetFor(r.infohash, r.title), source = "BitSearch",
            )
        }
    }
}

// ── Knaben ───────────────────────────────────────────────────────────────────
@Serializable
private data class KnabenRequest(
    val query: String,
    @SerialName("search_type") val searchType: String = "100%",
    @SerialName("search_field") val searchField: String = "title",
    @SerialName("order_by") val orderBy: String = "seeders",
    @SerialName("order_direction") val orderDirection: String = "desc",
    val size: Int = 50,
    @SerialName("hide_unsafe") val hideUnsafe: Boolean = true,
    @SerialName("hide_xxx") val hideXxx: Boolean = true,
)

@Serializable
private data class KnabenResponse(val hits: List<KnabenHit>? = null)

@Serializable
private data class KnabenHit(
    val hash: String? = null, val title: String? = null, val bytes: Long? = null,
    val seeders: Int? = null, val peers: Int? = null,
    @SerialName("magnetUrl") val magnetUrl: String? = null,
)

class KnabenSource : SearchSource {
    override val id = "knaben"
    override fun isEnabled() = true
    private val infohashRe = Regex("^([0-9a-fA-F]{40}|[A-Za-z2-7]{32})$")
    override suspend fun search(query: String): List<SearchResult> = withContext(Dispatchers.IO) {
        val reqBody = Http.json.encodeToString(KnabenRequest.serializer(), KnabenRequest(query = query))
        val resp = Http.postJson("https://api.knaben.org/v1", reqBody)
        if (!resp.ok) return@withContext emptyList()
        val body = runCatching { Http.json.decodeFromString<KnabenResponse>(resp.body) }.getOrNull() ?: return@withContext emptyList()
        body.hits.orEmpty().mapNotNull { h ->
            val hash = h.hash ?: return@mapNotNull null
            if (!infohashRe.matches(hash)) return@mapNotNull null
            val name = h.title.orEmpty()
            SearchResult(
                name = name, size = h.bytes ?: 0, seeders = h.seeders ?: 0, leechers = h.peers ?: 0,
                hash = hash.lowercase(),
                magnet = h.magnetUrl?.takeIf { it.isNotBlank() } ?: magnetFor(hash, name),
                source = "Knaben",
            )
        }
    }
}
