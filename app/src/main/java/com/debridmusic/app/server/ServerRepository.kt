package com.debridmusic.app.server

import com.debridmusic.app.data.local.SettingsStore
import com.google.gson.Gson
import kotlinx.coroutines.flow.first
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Talks to the self-hosted music server. The base URL is dynamic (the user's PC IP),
 * so this repository builds its own Retrofit at runtime. API calls carry the bearer
 * token via [ServerAuthInterceptor]; stream/art URLs carry it as a `?token=` query
 * param so ExoPlayer/Coil can fetch them through the shared OkHttp client unchanged.
 */
@Singleton
class ServerRepository @Inject constructor(
    private val okHttpClient: OkHttpClient,
    private val authInterceptor: ServerAuthInterceptor,
    private val settingsStore: SettingsStore,
) {
    @Volatile private var baseUrl: String = ""
    @Volatile private var token: String = ""
    @Volatile private var cachedApi: ServerApi? = null
    @Volatile private var cachedFor: String = ""

    /** Pushed from the settings flow when the URL/token changes. */
    fun configure(url: String, token: String) {
        baseUrl = url.trim().trimEnd('/')
        this.token = token.trim()
        authInterceptor.token = this.token
    }

    val isConfigured: Boolean get() = baseUrl.isNotBlank()

    private suspend fun ensureConfigured() {
        if (baseUrl.isBlank()) configure(settingsStore.serverUrl.first(), settingsStore.serverToken.first())
    }

    private suspend fun api(): ServerApi {
        ensureConfigured()
        cachedApi?.let { if (cachedFor == baseUrl) return it }
        val client = okHttpClient.newBuilder().addInterceptor(authInterceptor).build()
        val api = Retrofit.Builder()
            .baseUrl("$baseUrl/")
            .client(client)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
            .create(ServerApi::class.java)
        cachedApi = api; cachedFor = baseUrl
        return api
    }

    suspend fun testConnection(): Result<ServerHealthDto> = runCatching {
        require(baseUrl.isNotBlank() || settingsStore.serverUrl.first().isNotBlank()) { "Geen server-URL" }
        api().health()
    }

    suspend fun fetchCatalog(): ServerCatalogDto = api().catalog()

    suspend fun search(query: String): ServerSearchDto = api().search(query)

    /**
     * Trade the six digits shown on the PC for the access token, and remember the pairing.
     *
     * Builds its own Retrofit against [url] rather than going through [api]: at this point there
     * is no token to authenticate with, and the configured server may still be a different one.
     */
    suspend fun pair(url: String, code: String, deviceName: String): Result<ServerPairResponse> =
        runCatching {
            val base = url.trim().trimEnd('/')
            val plain = Retrofit.Builder()
                .baseUrl("$base/")
                .client(okHttpClient)
                .addConverterFactory(GsonConverterFactory.create())
                .build()
                .create(ServerApi::class.java)
            val response = plain.pair(ServerPairRequest(code.trim(), deviceName))
            require(response.token.isNotBlank()) { "Server gaf geen toegangscode terug" }
            settingsStore.setServerUrl(base)
            settingsStore.setServerToken(response.token)
            configure(base, response.token)
            // Drop the cached client: it was built for the previous server, or without a token.
            cachedApi = null
            cachedFor = ""
            response
        }

    // ── Shared state ─────────────────────────────────────────────────────────

    suspend fun fetchState(since: Long? = null): ServerStateDto = api().state(since)

    /** Push what happened on this device. Best-effort: a lost op is not worth an error dialog. */
    suspend fun pushOps(deviceId: String, deviceName: String, ops: List<Map<String, Any?>>): Result<ServerOpsResponse> =
        runCatching { api().pushOps(ServerOpsRequest(deviceId, deviceName, ops)) }

    suspend fun reportPlayed(trackId: String, deviceId: String, deviceName: String) {
        if (trackId.isBlank()) return
        pushOps(
            deviceId, deviceName,
            listOf(mapOf("type" to "played", "trackId" to trackId, "at" to System.currentTimeMillis())),
        )
    }

    suspend fun reportProgress(
        trackId: String,
        positionMs: Long,
        playing: Boolean,
        queue: List<String>,
        index: Int,
        deviceId: String,
        deviceName: String,
    ) {
        if (trackId.isBlank()) return
        pushOps(
            deviceId, deviceName,
            listOf(
                mapOf(
                    "type" to "progress",
                    "trackId" to trackId,
                    "positionMs" to positionMs,
                    "queue" to queue,
                    "index" to index,
                    "playing" to playing,
                    "at" to System.currentTimeMillis(),
                )
            ),
        )
    }

    suspend fun streamUrlFor(trackId: String): String {
        ensureConfigured()
        return "$baseUrl/stream/$trackId?token=$token"
    }

    suspend fun artUrlFor(artworkRef: String): String {
        ensureConfigured()
        return "$baseUrl/art/$artworkRef?token=$token"
    }

    /** Uploads a finished download into the server's library (Phase 3). */
    suspend fun ingest(file: File, title: String, artist: String, album: String, trackNo: Int, year: Int?): ServerIngestResponse {
        val body = file.asRequestBody("application/octet-stream".toMediaType())
        val filePart = MultipartBody.Part.createFormData("file", file.name, body)
        val meta = Gson().toJson(
            mapOf("title" to title, "artist" to artist, "album" to album, "trackNo" to trackNo, "year" to year)
        )
        return api().ingest(filePart, meta.toRequestBody("application/json".toMediaType()))
    }
}
