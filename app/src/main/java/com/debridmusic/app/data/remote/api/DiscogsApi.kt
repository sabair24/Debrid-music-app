package com.debridmusic.app.data.remote.api

import com.debridmusic.app.data.remote.dto.DiscogsArtistDetail
import com.debridmusic.app.data.remote.dto.DiscogsCollectionResponse
import com.debridmusic.app.data.remote.dto.DiscogsIdentity
import com.debridmusic.app.data.remote.dto.DiscogsRelease
import com.debridmusic.app.data.remote.dto.DiscogsSearchResponse
import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query

// Discogs database API. Auth (the user's token) + User-Agent are added by
// DiscogsAuthInterceptor; search endpoints require authentication.
interface DiscogsApi {
    // Verifies the token: returns the authenticated user, or HTTP 401 if invalid.
    @GET("oauth/identity")
    suspend fun identity(): DiscogsIdentity

    // Free-text search (used by the manual metadata picker).
    @GET("database/search")
    suspend fun search(
        @Query("q") query: String,
        @Query("type") type: String = "release",
        @Query("per_page") perPage: Int = 12,
    ): DiscogsSearchResponse

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

    // The user's collection ("All" folder = id 0), paginated.
    @GET("users/{username}/collection/folders/{folderId}/releases")
    suspend fun getCollectionReleases(
        @Path("username") username: String,
        @Path("folderId") folderId: Int = 0,
        @Query("page") page: Int = 1,
        @Query("per_page") perPage: Int = 100,
        @Query("sort") sort: String = "artist",
    ): DiscogsCollectionResponse
}
