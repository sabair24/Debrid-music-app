package com.debridmusic.app.data.remote.api

import com.debridmusic.app.data.remote.dto.TadbAlbumResponse
import com.debridmusic.app.data.remote.dto.TadbArtistResponse
import retrofit2.http.GET
import retrofit2.http.Query

// Base URL includes the free public API key path (see NetworkModule).
interface TheAudioDbApi {
    @GET("search.php")
    suspend fun searchArtist(@Query("s") name: String): TadbArtistResponse

    @GET("searchalbum.php")
    suspend fun searchAlbum(@Query("s") artist: String, @Query("a") album: String): TadbAlbumResponse

    @GET("artist-mb.php")
    suspend fun artistByMbid(@Query("i") mbid: String): TadbArtistResponse

    @GET("album-mb.php")
    suspend fun albumByMbid(@Query("i") mbid: String): TadbAlbumResponse
}
