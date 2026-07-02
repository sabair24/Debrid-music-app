package com.debridmusic.server.torbox

import com.debridmusic.server.net.Http
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.URLEncoder

/** Thin TorBox API client. The key is supplied per-call so settings changes take effect live. */
class TorBoxClient(private val apiKey: () -> String?) {
    private val base = "https://api.torbox.app/v1/api"

    private fun authHeaders(): Map<String, String> =
        apiKey()?.let { mapOf("Authorization" to "Bearer $it") } ?: emptyMap()

    fun hasKey(): Boolean = !apiKey().isNullOrBlank()

    /** Lowercased set of hashes TorBox reports as instantly cached. */
    suspend fun checkCached(hashes: List<String>): Set<String> = withContext(Dispatchers.IO) {
        if (hashes.isEmpty() || !hasKey()) return@withContext emptySet()
        val q = hashes.joinToString(",")
        val resp = Http.get("$base/torrents/checkcached?hash=${enc(q)}&format=list&list_files=false", authHeaders())
        if (!resp.ok) return@withContext emptySet()
        val parsed = runCatching { Http.json.decodeFromString<TbCachedResp>(resp.body) }.getOrNull() ?: return@withContext emptySet()
        parsed.data.orEmpty().mapNotNull { it.hash?.lowercase() }.toSet()
    }

    /** Add a torrent from a magnet; returns the raw create response (caller inspects success/detail). */
    suspend fun addMagnet(magnet: String): TbCreateResp = withContext(Dispatchers.IO) {
        val resp = Http.postForm("$base/torrents/createtorrent", mapOf("magnet" to magnet), authHeaders())
        runCatching { Http.json.decodeFromString<TbCreateResp>(resp.body) }
            .getOrElse { TbCreateResp(success = false, detail = "Bad TorBox response") }
    }

    /** All of the user's torrents (each carries its files). */
    suspend fun listTorrents(): List<TbTorrent> = withContext(Dispatchers.IO) {
        val resp = Http.get("$base/torrents/mylist?bypass_cache=true", authHeaders())
        if (!resp.ok) return@withContext emptyList()
        runCatching { Http.json.decodeFromString<TbListResp>(resp.body) }.getOrNull()?.data.orEmpty()
    }

    /** Final playable/downloadable URL for one file. Key is sent both as Bearer and ?token=. */
    suspend fun requestDownload(torrentId: Long, fileId: Long): String? = withContext(Dispatchers.IO) {
        val key = apiKey() ?: return@withContext null
        val url = "$base/torrents/requestdl?token=${enc(key)}&torrent_id=$torrentId&file_id=$fileId&zip_link=false"
        val resp = Http.get(url, authHeaders())
        if (!resp.ok) return@withContext null
        runCatching { Http.json.decodeFromString<TbDlResp>(resp.body) }.getOrNull()?.data?.takeIf { it.isNotBlank() }
    }

    suspend fun userInfo(): TbUser? = withContext(Dispatchers.IO) {
        val resp = Http.get("$base/user/me", authHeaders())
        if (!resp.ok) return@withContext null
        runCatching { Http.json.decodeFromString<TbUserResp>(resp.body) }.getOrNull()?.data
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
}
