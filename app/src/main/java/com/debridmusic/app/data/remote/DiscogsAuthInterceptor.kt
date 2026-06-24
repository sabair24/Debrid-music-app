package com.debridmusic.app.data.remote

import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Adds the user's Discogs personal access token (and the required User-Agent) to
 * every Discogs request. The token is synced from [SettingsStore] before use, the
 * same way [com.debridmusic.app.torbox.TorBoxAuthInterceptor] works for TorBox.
 */
@Singleton
class DiscogsAuthInterceptor @Inject constructor() : Interceptor {

    @Volatile var token: String = ""

    override fun intercept(chain: Interceptor.Chain): Response {
        val builder = chain.request().newBuilder()
            // Discogs rejects requests without a User-Agent (HTTP 403).
            .header("User-Agent", "DebridMusic/1.0 (android)")
        if (token.isNotBlank()) {
            builder.header("Authorization", "Discogs token=$token")
        }
        return chain.proceed(builder.build())
    }
}
