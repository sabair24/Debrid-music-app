package com.debridmusic.app.soulseek

import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.scanner.MediaScanner
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SoulseekRepository @Inject constructor(
    private val client: SoulseekClient,
    private val settingsStore: SettingsStore,
    private val libraryPublisher: LibraryPublisher,
    private val mediaScanner: MediaScanner,
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

    suspend fun testLogin(username: String, password: String): Result<Unit> =
        client.testLogin(username, password)

    fun download(file: SoulseekFile): Flow<SlskDownloadState> = flow {
        val (username, password) = credentials()
        client.download(username, password, file).collect { state ->
            if (state is SlskDownloadState.Done) {
                // Move the file into the public Music library and refresh the
                // in-app library so it shows up under the user's collection.
                val publishedUri = runCatching {
                    libraryPublisher.publish(state.localPath, file.displayName, file.username)
                }.getOrNull()
                runCatching { mediaScanner.scanDevice() }
                emit(SlskDownloadState.Done(publishedUri ?: state.localPath))
            } else {
                emit(state)
            }
        }
    }.catch { e -> emit(SlskDownloadState.Error(e.message ?: "Download failed")) }
}
