package com.debridmusic.server.net

import kotlinx.serialization.json.Json
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration

/** Shared, dependency-free HTTP client for the ported TorBox / search / metadata code. */
object Http {
    val json = Json { ignoreUnknownKeys = true; isLenient = true; encodeDefaults = true }

    private val client: HttpClient = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(12))
        .followRedirects(HttpClient.Redirect.NORMAL)
        .build()

    data class Resp(val code: Int, val body: String, val bytes: ByteArray, val headers: Map<String, List<String>>) {
        val ok: Boolean get() = code in 200..299
    }

    private const val UA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

    fun get(url: String, headers: Map<String, String> = emptyMap(), timeoutMs: Long = 15_000): Resp =
        send(builder(url, timeoutMs, headers).GET().build())

    fun postForm(url: String, form: Map<String, String>, headers: Map<String, String> = emptyMap(), timeoutMs: Long = 15_000): Resp {
        val body = form.entries.joinToString("&") { (k, v) ->
            "${enc(k)}=${enc(v)}"
        }
        val b = builder(url, timeoutMs, headers + ("Content-Type" to "application/x-www-form-urlencoded"))
        return send(b.POST(HttpRequest.BodyPublishers.ofString(body)).build())
    }

    fun postJson(url: String, jsonBody: String, headers: Map<String, String> = emptyMap(), timeoutMs: Long = 15_000): Resp {
        val b = builder(url, timeoutMs, headers + ("Content-Type" to "application/json"))
        return send(b.POST(HttpRequest.BodyPublishers.ofString(jsonBody)).build())
    }

    private fun builder(url: String, timeoutMs: Long, headers: Map<String, String>): HttpRequest.Builder {
        val b = HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofMillis(timeoutMs))
        b.header("User-Agent", UA)
        headers.forEach { (k, v) -> b.header(k, v) }
        return b
    }

    private fun send(req: HttpRequest): Resp {
        val resp = client.send(req, HttpResponse.BodyHandlers.ofByteArray())
        val bytes = resp.body() ?: ByteArray(0)
        return Resp(resp.statusCode(), bytes.decodeToString(), bytes, resp.headers().map())
    }

    private fun enc(s: String) = java.net.URLEncoder.encode(s, Charsets.UTF_8)
}
