package com.debridmusic.app.data.remote.api

import com.debridmusic.app.data.remote.dto.DiscogsArtistDetail
import com.debridmusic.app.data.remote.dto.DiscogsRelease
import com.debridmusic.app.data.remote.dto.DiscogsSearchResponse
import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query

// Discogs database API. Auth (the user's token) + User-Agent are added by
// DiscogsAuthInterceptor; search endpoints require authentication.
interface DiscogsApi {
    @GET("database/search")
    suspend fun searchRelease(
        @Query("release_title") releaseTitle: String,
        @Query("artist") artist: String,
        @Query("type") type: String = "release",
        @Query("per_page") perPage: Int = 5,
    ): DiscogsSearchResponse

    @GET("releases/{id}")
    suspend fun getRelease(@Path("id") id: Long): DiscogsRelease

    @GET("database/search")
    suspend fun searchArtist(
        @Query("q") query: String,
        @Query("type") type: String = "artist",
        @Query("per_page") perPage: Int = 5,
    ): DiscogsSearchResponse

    @GET("artists/{id}")
    suspend fun getArtist(@Path("id") id: Long): DiscogsArtistDetail
}
