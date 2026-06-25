package com.debridmusic.app.server

import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject
import javax.inject.Singleton

/** Adds the music-server bearer token to API requests (mirrors TorBoxAuthInterceptor). */
@Singleton
class ServerAuthInterceptor @Inject constructor() : Interceptor {

    @Volatile var token: String = ""

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = if (token.isNotBlank()) {
            chain.request().newBuilder().header("Authorization", "Bearer $token").build()
        } else {
            chain.request()
        }
        return chain.proceed(request)
    }
}
