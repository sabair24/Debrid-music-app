package com.debridmusic.app.data.remote.api

import com.debridmusic.app.data.remote.dto.KnabenRequest
import com.debridmusic.app.data.remote.dto.KnabenResponse
import retrofit2.http.Body
import retrofit2.http.POST

// Knaben aggregator API (api.knaben.org). No auth; JSON POST.
interface KnabenApi {
    @POST("v1")
    suspend fun search(@Body request: KnabenRequest): KnabenResponse
}
