package com.debridmusic.app.search.sources

import android.util.Log
import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.search.SearchSource
import com.debridmusic.app.search.magnetFor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.FormBody
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import java.io.ByteArrayInputStream
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/**
 * RuTracker search source. Fragile by nature: requires the user's login, scrapes
 * windows-1251 HTML, and resolves magnets per-topic. Everything is wrapped so any
 * failure (login, CAPTCHA, ISP block, markup change) yields an empty list rather
 * than breaking the aggregate search. Disabled unless credentials are set.
 */
@Singleton
class RuTrackerSource @Inject constructor(
    baseClient: OkHttpClient,
    private val settingsStore: SettingsStore,
) : SearchSource {
    override val id = "rutracker"

    private val cookieJar = object : CookieJar {
        private val store = ConcurrentHashMap<String, MutableMap<String, Cookie>>()
        override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
            val host = store.getOrPut(url.host) { ConcurrentHashMap() }
            cookies.forEach { host[it.name] = it }
        }
        override fun loadForRequest(url: HttpUrl): List<Cookie> =
            store[url.host]?.values?.toList() ?: emptyList()
    }

    private val client: OkHttpClient = baseClient.newBuilder()
        .cookieJar(cookieJar)
        .followRedirects(true)
        .build()

    @Volatile private var loggedIn = false

    override suspend fun isEnabled(): Boolean = settingsStore.ruTrackerUsername.first().isNotBlank()

    override suspend fun search(query: String): List<TorBoxSearchResult> = withContext(Dispatchers.IO) {
        if (!ensureLoggedIn()) return@withContext emptyList()
        val rows = runCatching { fetchRows(query) }.getOrElse {
            Log.d(TAG, "search failed: ${it.message}"); emptyList()
        }
        // Resolve magnets for the top results only (each needs a topic-page fetch).
        coroutineScope {
            rows.sortedByDescending { it.seeders }.take(MAX_RESULTS).map { row ->
                async {
                    val magnet = runCatching { fetchMagnet(row.topicId) }.getOrNull() ?: return@async null
                    val hash = HASH_RE.find(magnet)?.groupValues?.get(1)?.lowercase() ?: return@async null
                    TorBoxSearchResult(
                        rawTitle = row.title, name = row.title, size = row.size,
                        seeders = row.seeders, leechers = row.leechers,
                        magnet = magnet, hash = hash, source = "RuTracker",
                    )
                }
            }.awaitAll().filterNotNull()
        }
    }

    private suspend fun ensureLoggedIn(): Boolean {
        if (loggedIn) return true
        val user = settingsStore.ruTrackerUsername.first()
        val pass = settingsStore.ruTrackerPassword.first()
        if (user.isBlank() || pass.isBlank()) return false
        return runCatching {
            val body = FormBody.Builder()
                .add("login_username", user)
                .add("login_password", pass)
                .add("login", "Вход")
                .build()
            val req = Request.Builder().url("$BASE/login.php").post(body)
                .header("User-Agent", UA).build()
            client.newCall(req).execute().use { resp ->
                val html = resp.body?.bytes()?.let { String(it, charset("windows-1251")) } ?: ""
                if (html.contains("cap_sid") || html.contains("captcha", true)) {
                    Log.d(TAG, "login needs CAPTCHA — user must log in via browser once")
                    return@runCatching false
                }
            }
            // We're logged in if the session cookie is now present.
            loggedIn = cookieJar.loadForRequest("$BASE/".toHttpUrlOrNull()!!).any { it.name == "bb_session" }
            loggedIn
        }.getOrDefault(false)
    }

    private data class Row(val topicId: String, val title: String, val size: Long, val seeders: Int, val leechers: Int)

    private fun fetchRows(query: String): List<Row> {
        val url = "$BASE/tracker.php".toHttpUrlOrNull()!!.newBuilder().addQueryParameter("nm", query).build()
        val req = Request.Builder().url(url).header("User-Agent", UA).build()
        client.newCall(req).execute().use { resp ->
            val bytes = resp.body?.bytes() ?: return emptyList()
            val doc = Jsoup.parse(ByteArrayInputStream(bytes), "windows-1251", BASE)
            return doc.select("tr.tCenter.hl-tr").mapNotNull { tr ->
                val link = tr.selectFirst("a.tLink, a.t-title-col, div.t-title a") ?: return@mapNotNull null
                val href = link.attr("href") // viewtopic.php?t=ID
                val topicId = Regex("t=(\\d+)").find(href)?.groupValues?.get(1) ?: return@mapNotNull null
                val title = link.text().ifBlank { return@mapNotNull null }
                val size = tr.selectFirst("td.tor-size, td[data-ts_text]")?.attr("data-ts_text")?.toLongOrNull() ?: 0L
                val seeders = tr.selectFirst("b.seedmed, td.seedmed b, .seedmed")?.text()?.trim()?.toIntOrNull() ?: 0
                val leechers = tr.selectFirst("td.leechmed, .leechmed")?.text()?.trim()?.toIntOrNull() ?: 0
                Row(topicId, title, size, seeders, leechers)
            }
        }
    }

    private fun fetchMagnet(topicId: String): String? {
        val req = Request.Builder().url("$BASE/viewtopic.php?t=$topicId").header("User-Agent", UA).build()
        client.newCall(req).execute().use { resp ->
            val bytes = resp.body?.bytes() ?: return null
            val html = String(bytes, charset("windows-1251"))
            return HASH_RE.find(html)?.value
        }
    }

    companion object {
        private const val TAG = "RuTrackerSource"
        private const val BASE = "https://rutracker.org/forum"
        private const val UA = "Mozilla/5.0 (Android) DebridMusic"
        private const val MAX_RESULTS = 10
        private val HASH_RE = Regex("magnet:\\?xt=urn:btih:([A-Za-z0-9]+)[^\"'\\s<]*")
    }
}
