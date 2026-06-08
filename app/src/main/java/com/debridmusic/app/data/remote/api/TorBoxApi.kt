package com.debridmusic.app.data.remote.api

import com.debridmusic.app.data.remote.dto.TorBoxCreateData
import com.debridmusic.app.data.remote.dto.TorBoxResponse
import com.debridmusic.app.data.remote.dto.TorBoxTorrentItem
import com.debridmusic.app.data.remote.dto.TorBoxUser
import retrofit2.http.Field
import retrofit2.http.FormUrlEncoded
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Query

interface TorBoxApi {

    @FormUrlEncoded
    @POST("api/torrents/createtorrent")
    suspend fun addMagnet(
        @Field("magnet") magnet: String,
    ): TorBoxResponse<TorBoxCreateData>

    @GET("api/torrents/mylist")
    suspend fun listTorrents(
        @Query("bypass_cache") bypassCache: Boolean = true,
    ): TorBoxResponse<List<TorBoxTorrentItem>>

    @GET("api/torrents/requestdl")
    suspend fun requestDownload(
        @Query("token") token: String,
        @Query("torrent_id") torrentId: Long,
        @Query("file_id") fileId: Long,
        @Query("zip_link") zipLink: Boolean = false,
    ): TorBoxResponse<String>

    @GET("api/user/me")
    suspend fun getUserInfo(): TorBoxResponse<TorBoxUser>
}
