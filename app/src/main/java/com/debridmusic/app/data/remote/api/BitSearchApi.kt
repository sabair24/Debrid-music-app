package com.debridmusic.app.data.remote.api

import com.debridmusic.app.data.remote.dto.BitSearchResponse
import retrofit2.http.GET
import retrofit2.http.Query

interface BitSearchApi {

    @GET("api/v1/search")
    suspend fun search(
        @Query("q") query: String,
        @Query("category") category: String = "audio",
        @Query("sort") sort: String = "seeders",
        @Query("p") page: Int = 1,
    ): BitSearchResponse
}
