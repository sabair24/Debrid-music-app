package com.debridmusic.app.server

import okhttp3.MultipartBody
import okhttp3.RequestBody
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Multipart
import retrofit2.http.POST
import retrofit2.http.Part
import retrofit2.http.Query

interface ServerApi {
    @GET("health")
    suspend fun health(): ServerHealthDto

    @GET("api/catalog")
    suspend fun catalog(): ServerCatalogDto

    @GET("api/search")
    suspend fun search(@Query("q") query: String): ServerSearchDto

    /**
     * Trade the six digits shown on the PC for the real access token.
     *
     * Unauthenticated by nature — it is how a device with no token gets one.
     */
    @POST("pair")
    suspend fun pair(@Body request: ServerPairRequest): ServerPairResponse

    // ── Shared state: playlists, favourites, play position, play counts ───────
    @GET("api/state")
    suspend fun state(@Query("since") since: Long? = null): ServerStateDto

    @POST("api/state/ops")
    suspend fun pushOps(@Body request: ServerOpsRequest): ServerOpsResponse

    @Multipart
    @POST("api/ingest")
    suspend fun ingest(
        @Part file: MultipartBody.Part,
        @Part("metadata") metadata: RequestBody,
    ): ServerIngestResponse
}
