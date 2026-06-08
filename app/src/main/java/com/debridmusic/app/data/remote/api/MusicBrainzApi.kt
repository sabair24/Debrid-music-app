package com.debridmusic.app.data.remote.api

import com.debridmusic.app.data.remote.dto.MbArtistSearchResult
import com.debridmusic.app.data.remote.dto.MbRelease
import com.debridmusic.app.data.remote.dto.MbReleaseSearchResult
import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query

interface MusicBrainzApi {

    @GET("release")
    suspend fun searchRelease(
        @Query("query") query: String,
        @Query("limit") limit: Int = 5,
        @Query("fmt") format: String = "json",
    ): MbReleaseSearchResult

    @GET("artist")
    suspend fun searchArtist(
        @Query("query") query: String,
        @Query("limit") limit: Int = 5,
        @Query("fmt") format: String = "json",
    ): MbArtistSearchResult

    @GET("release/{mbid}")
    suspend fun getRelease(
        @Path("mbid") mbid: String,
        @Query("inc") inc: String = "recordings+artists+release-groups",
        @Query("fmt") format: String = "json",
    ): MbRelease
}
