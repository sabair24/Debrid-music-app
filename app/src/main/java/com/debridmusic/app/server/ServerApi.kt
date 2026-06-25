package com.debridmusic.app.server

import okhttp3.MultipartBody
import okhttp3.RequestBody
import retrofit2.http.GET
import retrofit2.http.Multipart
import retrofit2.http.POST
import retrofit2.http.Part

interface ServerApi {
    @GET("health")
    suspend fun health(): ServerHealthDto

    @GET("api/catalog")
    suspend fun catalog(): ServerCatalogDto

    @Multipart
    @POST("api/ingest")
    suspend fun ingest(
        @Part file: MultipartBody.Part,
        @Part("metadata") metadata: RequestBody,
    ): ServerIngestResponse
}
