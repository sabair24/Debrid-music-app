package com.debridmusic.app.data.remote.api

import com.debridmusic.app.data.remote.dto.LastFmAlbumResponse
import com.debridmusic.app.data.remote.dto.LastFmArtistResponse
import retrofit2.http.GET
import retrofit2.http.Query

interface LastFmApi {

    @GET(".")
    suspend fun getArtistInfo(
        @Query("method") method: String = "artist.getInfo",
        @Query("artist") artist: String,
        @Query("api_key") apiKey: String,
        @Query("format") format: String = "json",
        @Query("autocorrect") autocorrect: Int = 1,
        @Query("lang") lang: String = "en",
    ): LastFmArtistResponse

    @GET(".")
    suspend fun getAlbumInfo(
        @Query("method") method: String = "album.getInfo",
        @Query("artist") artist: String,
        @Query("album") album: String,
        @Query("api_key") apiKey: String,
        @Query("format") format: String = "json",
        @Query("autocorrect") autocorrect: Int = 1,
    ): LastFmAlbumResponse
}
