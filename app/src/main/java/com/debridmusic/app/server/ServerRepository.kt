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
