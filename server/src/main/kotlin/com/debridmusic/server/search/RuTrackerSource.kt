package com.debridmusic.server.search

import com.debridmusic.server.ServerSettings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jsoup.Jsoup
import org.slf4j.LoggerFactory
import java.net.CookieManager
import java.net.CookiePolicy
import java.net.URI
import java.net.URLEncoder
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.charset.Charset
import java.time.Duration

/**
 * RuTracker source: form login (cookie session) + tracker.php scrape (windows-1251) +
 * lazy magnet resolution from viewtopic pages. Enabled only when credentials are set.
 * Detects the login CAPTCHA and bails (user must sign in via a browser once).
 */
class RuTrackerSource(private val settings: ServerSettings) : SearchSource {
    override val id = "rutracker"
    private val log = LoggerFactory.getLogger(RuTrackerSource::class.java)

    private val base = "https://rutracker.org/forum"
    private val cp1251: Charset = Charset.forName("windows-1251")
    private val cookies = CookieManager().apply { setCookiePolicy(CookiePolicy.ACCEPT_ALL) }
    private val client = HttpClient.newBuilder()
        .cookieHandler(cookies)
        .connectTimeout(Duration.ofSeconds(12))
        .followRedirects(HttpClient.Redirect.NORMAL)
        .build()

    @Volatile private var loggedIn = false

    override fun isEnabled() = settings.get(ServerSettings.RUTRACKER_USER) != null &&
        settings.get(ServerSettings.RUTRACKER_PASS) != null

    override suspend fun search(query: String): List<SearchResult> = withContext(Dispatchers.IO) {
        if (!isEnabled() || !ensureLoggedIn()) return@withContext emptyList()
        val rows = fetchRows(query)
        rows.sortedByDescending { it.seeders }.take(MAX_RESULTS).mapNotNull { row ->
            val hash = fetchMagnetHash(row.topicId) ?: return@mapNotNull null
            SearchResult(
                name = row.title, size = row.size, seeders = row.seeders, leechers = row.leechers,
                hash = hash.lowercase(), magnet = magnetFor(hash, row.title), source = "RuTracker",
            )
        }
    }

    private data class Row(val topicId: String, val title: String, val size: Long, val seeders: Int, val leechers: Int)

    private fun ensureLoggedIn(): Boolean {
        if (loggedIn) return true
        val user = settings.get(ServerSettings.RUTRACKER_USER) ?: return false
        val pass = settings.get(ServerSettings.RUTRACKER_PASS) ?: return false
        return runCatching {
            val form = mapOf("login_username" to user, "login_password" to pass, "login" to "Вход")
                .entries.joinToString("&") { (k, v) -> "$k=${URLEncoder.encode(v, cp1251)}" }
            val req = HttpRequest.newBuilder(URI.create("$base/login.php"))
                .header("User-Agent", "Mozilla/5.0 (Android) DebridMusic")
                .header("Content-Type", "application/x-www-form-urlencoded")
                .timeout(Duration.ofSeconds(15))
                .POST(HttpRequest.BodyPublishers.ofByteArray(form.toByteArray(cp1251)))
                .build()
            val resp = client.send(req, HttpResponse.BodyHandlers.ofByteArray())
            val html = String(resp.body(), cp1251)
            if (html.contains("cap_sid") || html.contains("captcha", ignoreCase = true)) {
                log.warn("RuTracker requires CAPTCHA — sign in via a browser once."); return false
            }
            loggedIn = cookies.cookieStore.cookies.any { it.name == "bb_session" }
            loggedIn
        }.getOrElse { log.warn("RuTracker login failed: {}", it.message); false }
    }

    private fun fetchRows(query: String): List<Row> = runCatching {
        val bytes = get("$base/tracker.php?nm=${URLEncoder.encode(query, cp1251)}")
        val doc = Jsoup.parse(bytes.inputStream(), "windows-1251", base)
        doc.select("tr.tCenter.hl-tr").mapNotNull { tr ->
            val link = tr.selectFirst("a.tLink, a.t-title-col, div.t-title a") ?: return@mapNotNull null
            val topicId = Regex("t=(\\d+)").find(link.attr("href"))?.groupValues?.get(1) ?: return@mapNotNull null
            val size = tr.selectFirst("td.tor-size, td[data-ts_text]")?.attr("data-ts_text")?.toLongOrNull() ?: 0
            val seeders = tr.selectFirst("b.seedmed, td.seedmed b, .seedmed")?.text()?.trim()?.toIntOrNull() ?: 0
            val leechers = tr.selectFirst("td.leechmed, .leechmed")?.text()?.trim()?.toIntOrNull() ?: 0
            Row(topicId, link.text().trim(), size, seeders, leechers)
        }
    }.getOrDefault(emptyList())

    private fun fetchMagnetHash(topicId: String): String? = runCatching {
        val bytes = get("$base/viewtopic.php?t=$topicId")
        val html = String(bytes, cp1251)
        Regex("magnet:\\?xt=urn:btih:([A-Za-z0-9]+)[^\"'\\s<]*").find(html)?.groupValues?.get(1)
    }.getOrNull()

    private fun get(url: String): ByteArray {
        val req = HttpRequest.newBuilder(URI.create(url))
            .header("User-Agent", "Mozilla/5.0 (Android) DebridMusic")
            .timeout(Duration.ofSeconds(15)).GET().build()
        return client.send(req, HttpResponse.BodyHandlers.ofByteArray()).body() ?: ByteArray(0)
    }

    companion object { const val MAX_RESULTS = 10 }
}
