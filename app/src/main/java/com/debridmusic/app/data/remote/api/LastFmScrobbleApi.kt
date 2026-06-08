package com.debridmusic.app.data.remote.api

import com.debridmusic.app.data.remote.dto.LastFmNowPlayingResponse
import com.debridmusic.app.data.remote.dto.LastFmScrobbleResponse
import com.debridmusic.app.data.remote.dto.LastFmSessionResponse
import retrofit2.http.Field
import retrofit2.http.FieldMap
import retrofit2.http.FormUrlEncoded
import retrofit2.http.POST

interface LastFmScrobbleApi {

    @POST(".")
    @FormUrlEncoded
    suspend fun getMobileSession(
        @Field("method") method: String = "auth.getMobileSession",
        @Field("username") username: String,
        @Field("password") password: String,
        @Field("api_key") apiKey: String,
        @Field("api_sig") apiSig: String,
        @Field("format") format: String = "json",
    ): LastFmSessionResponse

    @POST(".")
    @FormUrlEncoded
    suspend fun scrobble(@FieldMap params: Map<String, String>): LastFmScrobbleResponse

    @POST(".")
    @FormUrlEncoded
    suspend fun updateNowPlaying(@FieldMap params: Map<String, String>): LastFmNowPlayingResponse
}
