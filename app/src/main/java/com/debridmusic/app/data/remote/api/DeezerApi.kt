package com.debridmusic.app.data.remote.api

import com.debridmusic.app.data.remote.dto.DeezerAlbum
import com.debridmusic.app.data.remote.dto.DeezerArtist
import com.debridmusic.app.data.remote.dto.DeezerSearchResponse
import com.debridmusic.app.data.remote.dto.DeezerTrack
import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query

interface DeezerApi {
    @GET("search/artist")
    suspend fun searchArtist(@Query("q") q: String, @Query("limit") limit: Int = 8): DeezerSearchResponse<DeezerArtist>

    @GET("artist/{id}")
    suspend fun getArtist(@Path("id") id: Long): DeezerArtist

    @GET("search/album")
    suspend fun searchAlbum(@Query("q") q: String, @Query("limit") limit: Int = 8): DeezerSearchResponse<DeezerAlbum>

    @GET("album/{id}")
    suspend fun getAlbum(@Path("id") id: Long): DeezerAlbum

    // ── Discography (browse-by-artist) ──────────────────────────────────────────
    @GET("artist/{id}/albums")
    suspend fun artistAlbums(@Path("id") id: Long, @Query("limit") limit: Int = 100): DeezerSearchResponse<DeezerAlbum>

    @GET("artist/{id}/top")
    suspend fun artistTopTracks(@Path("id") id: Long, @Query("limit") limit: Int = 25): DeezerSearchResponse<DeezerTrack>

    @GET("album/{id}/tracks")
    suspend fun albumTracks(@Path("id") id: Long): DeezerSearchResponse<DeezerTrack>
}
