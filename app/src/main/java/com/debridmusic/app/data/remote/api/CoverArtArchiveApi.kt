package com.debridmusic.app.data.remote.api

import com.debridmusic.app.data.remote.dto.CoverArtResponse
import retrofit2.http.GET
import retrofit2.http.Path

interface CoverArtArchiveApi {

    @GET("release/{mbid}")
    suspend fun getCoverArt(@Path("mbid") mbid: String): CoverArtResponse
}
