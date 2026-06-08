package com.debridmusic.app.torbox

import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TorBoxAuthInterceptor @Inject constructor() : Interceptor {

    @Volatile var apiKey: String = ""

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = if (apiKey.isNotBlank()) {
            chain.request().newBuilder()
                .header("Authorization", "Bearer $apiKey")
                .build()
        } else {
            chain.request()
        }
        return chain.proceed(request)
    }
}
