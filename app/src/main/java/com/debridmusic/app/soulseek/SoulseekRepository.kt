package com.debridmusic.app.soulseek

import com.debridmusic.app.data.local.SettingsStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SoulseekRepository @Inject constructor(
    private val client: SoulseekClient,
    private val settingsStore: SettingsStore,
) {
    private suspend fun credentials(): Pair<String, String> {
        val username = settingsStore.slskUsername.first()
        val password = settingsStore.slskPassword.first()
        if (username.isBlank()) error("Soulseek username not configured — add it in Settings")
        if (password.isBlank()) error("Soulseek password not configured — add it in Settings")
        return username to password
    }

    suspend fun search(query: String): Result<List<SoulseekFile>> {
        val creds = runCatching { credentials() }.getOrElse { return Result.failure(it) }
        return client.search(creds.first, creds.second, query)
    }

    fun download(file: SoulseekFile): Flow<SlskDownloadState> = flow {
        val (username, password) = credentials()
        emitAll(client.download(username, password, file))
    }.catch { e -> emit(SlskDownloadState.Error(e.message ?: "Download failed")) }
}
