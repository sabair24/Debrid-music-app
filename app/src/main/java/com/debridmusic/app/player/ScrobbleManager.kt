package com.debridmusic.app.player

import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.remote.api.LastFmScrobbleApi
import com.debridmusic.app.domain.model.Track
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ScrobbleManager @Inject constructor(
    private val settingsStore: SettingsStore,
    private val scrobbleApi: LastFmScrobbleApi,
) {
    private var lastScrobbledTrackId: Long? = null
    private var lastNowPlayingTrackId: Long? = null

    fun init(playerController: PlayerController, scope: CoroutineScope) {
        scope.launch {
            combine(
                playerController.currentTrack,
                playerController.positionMs,
                playerController.durationMs,
                settingsStore.lastFmSessionKey,
                settingsStore.lastFmApiKey,
            ) { track, pos, dur, sk, apiKey ->
                Quint(track, pos, dur, sk, apiKey)
            }.collect { (track, pos, dur, sk, apiKey) ->
                if (sk.isBlank() || apiKey.isBlank() || track == null || track.id == -1L) return@collect
                updateNowPlaying(track, sk, apiKey, scope)
                maybeScrobble(track, pos, dur, sk, apiKey, scope)
            }
        }
    }

    private fun updateNowPlaying(
        track: Track,
        sessionKey: String,
        apiKey: String,
        scope: CoroutineScope,
    ) {
        if (track.id == lastNowPlayingTrackId) return
        lastNowPlayingTrackId = track.id
        scope.launch {
            runCatching {
                val secret = settingsStore.lastFmApiSecret.value
                val params = mutableMapOf(
                    "method" to "track.updateNowPlaying",
                    "artist" to track.artistName,
                    "track" to track.title,
                    "api_key" to apiKey,
                    "sk" to sessionKey,
                    "format" to "json",
                )
                params["api_sig"] = computeSig(params.filterKeys { it != "format" }, secret)
                scrobbleApi.updateNowPlaying(params)
            }
        }
    }

    private fun maybeScrobble(
        track: Track,
        positionMs: Long,
        durationMs: Long,
        sessionKey: String,
        apiKey: String,
        scope: CoroutineScope,
    ) {
        if (durationMs <= 0 || track.id == lastScrobbledTrackId) return
        val threshold = minOf(durationMs / 2, 240_000L)
        if (positionMs < threshold) return
        lastScrobbledTrackId = track.id
        scope.launch {
            runCatching {
                val secret = settingsStore.lastFmApiSecret.value
                val ts = (System.currentTimeMillis() / 1000L).toString()
                val params = mutableMapOf(
                    "method" to "track.scrobble",
                    "artist[0]" to track.artistName,
                    "track[0]" to track.title,
                    "timestamp[0]" to ts,
                    "api_key" to apiKey,
                    "sk" to sessionKey,
                    "format" to "json",
                )
                params["api_sig"] = computeSig(params.filterKeys { it != "format" }, secret)
                scrobbleApi.scrobble(params)
            }
        }
    }

    suspend fun login(
        username: String,
        password: String,
        apiKey: String,
        apiSecret: String,
    ): Result<String> = runCatching {
        val params = mapOf(
            "method" to "auth.getMobileSession",
            "username" to username,
            "password" to password,
            "api_key" to apiKey,
        )
        val sig = computeSig(params, apiSecret)
        val response = scrobbleApi.getMobileSession(
            username = username,
            password = password,
            apiKey = apiKey,
            apiSig = sig,
        )
        if (response.error != null) error(response.message ?: "Last.fm error ${response.error}")
        val sessionKey = response.session?.key ?: error("No session key")
        settingsStore.setLastFmSessionKey(sessionKey)
        settingsStore.setLastFmUsername(username)
        settingsStore.setLastFmApiSecret(apiSecret)
        sessionKey
    }

    private fun computeSig(params: Map<String, String>, secret: String): String {
        val sorted = params.entries
            .sortedBy { it.key }
            .joinToString("") { "${it.key}${it.value}" }
        return md5(sorted + secret)
    }

    private fun md5(input: String): String {
        val bytes = MessageDigest.getInstance("MD5").digest(input.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}

private data class Quint<A, B, C, D, E>(val a: A, val b: B, val c: C, val d: D, val e: E)

private operator fun <A, B, C, D, E> Quint<A, B, C, D, E>.component1() = a
private operator fun <A, B, C, D, E> Quint<A, B, C, D, E>.component2() = b
private operator fun <A, B, C, D, E> Quint<A, B, C, D, E>.component3() = c
private operator fun <A, B, C, D, E> Quint<A, B, C, D, E>.component4() = d
private operator fun <A, B, C, D, E> Quint<A, B, C, D, E>.component5() = e
