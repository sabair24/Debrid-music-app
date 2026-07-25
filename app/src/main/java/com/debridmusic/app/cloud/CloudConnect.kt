package com.debridmusic.app.cloud

import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.server.ServerRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import javax.inject.Inject
import javax.inject.Singleton

/**
 * From "signed in" to "connected to the PC".
 *
 * Lands in exactly the place the pairing code landed — [SettingsStore.serverUrl] and
 * [SettingsStore.serverToken], then [ServerRepository.configure] — so nothing downstream knows or
 * cares which of the two got it there.
 */
@Singleton
class CloudConnect @Inject constructor(
    private val session: CloudSession,
    private val serverRepository: ServerRepository,
    private val settingsStore: SettingsStore,
    private val okHttpClient: OkHttpClient,
) {
    sealed interface Result {
        data class Connected(val serverName: String, val url: String) : Result
        /** Signed in, but no PC has published itself under this account yet. */
        data object NoServer : Result
        /** The PC is known but has not answered — which is what "switched off" looks like. */
        data class Waiting(val serverName: String) : Result
        /** Access granted, but no published address answers from this network. */
        data class Unreachable(val serverName: String) : Result

        /**
         * What to put on screen. Here rather than in each screen because the TV and the phone show
         * the same four outcomes, and four sentences maintained twice become two different
         * explanations of the same state.
         */
        val sentence: String
            get() = when (this) {
                is Connected -> "Verbonden met $serverName."
                NoServer -> "Nog geen pc onder dit account. Log op je pc in met hetzelfde account."
                is Waiting -> "$serverName heeft nog niet geantwoord. Zet hem aan — je aanvraag blijft staan."
                is Unreachable -> "$serverName gaf toegang, maar is op dit netwerk niet bereikbaar."
            }
    }

    /**
     * Find the PC, ask for access, and connect to whichever of its addresses answers.
     *
     * Every address is tried rather than only the first: a machine with a VPN, Hyper-V or two
     * network cards publishes several, and only this device can tell which one it can reach.
     */
    suspend fun connect(): Result {
        val servers = session.servers()
        if (servers.isEmpty()) return Result.NoServer

        val server = servers.firstOrNull { it.online && it.isFresh } ?: servers.first()
        val token = session.awaitAccess(server.id) ?: return Result.Waiting(server.name)

        for (url in server.urls) {
            val base = url.trim().trimEnd('/')
            if (base.isBlank()) continue
            if (!reachable(base)) continue
            settingsStore.setServerUrl(base)
            settingsStore.setServerToken(token)
            serverRepository.configure(base, token)
            return Result.Connected(server.name, base)
        }
        return Result.Unreachable(server.name)
    }

    /**
     * Does this address answer? Asked without a token on purpose — /health is the one route that
     * needs none, so a "no" here means unreachable rather than unauthorised.
     *
     * On [Dispatchers.IO], and that is not a detail. `execute()` blocks, and every caller reaches
     * this from `viewModelScope.launch`, which is the main thread: Android answers a blocking
     * network call there with NetworkOnMainThreadException. `runCatching` then swallows it and
     * reports the address as unreachable — so a PC on the same wifi, answering /health perfectly,
     * was refused on every network there is. The rest of the flow uses Retrofit's suspend
     * functions, which move themselves off the main thread, which is why sign-in and the grant
     * worked and only this last step failed.
     */
    private suspend fun reachable(base: String): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            okHttpClient.newBuilder()
                .callTimeout(java.time.Duration.ofSeconds(4))
                .build()
                .newCall(Request.Builder().url("$base/health").build())
                .execute()
                .use { it.isSuccessful }
        }.getOrDefault(false)
    }
}
