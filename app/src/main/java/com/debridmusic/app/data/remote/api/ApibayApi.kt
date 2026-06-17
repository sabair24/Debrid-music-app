package com.debridmusic.app.data.remote.api

import com.debridmusic.app.data.remote.dto.ApibayResult
import retrofit2.http.GET
import retrofit2.http.Query

// The Pirate Bay's JSON API (apibay.org). No auth. cat=100 = Audio top category.
interface ApibayApi {
    @GET("q.php")
    suspend fun search(
        @Query("q") query: String,
        @Query("cat") category: String = "100",
    ): List<ApibayResult>
}
