package com.debridmusic.app.torbox

import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.remote.api.TorBoxApi
import com.debridmusic.app.data.remote.dto.TorBoxFile
import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.data.remote.dto.TorBoxTorrentItem
import com.debridmusic.app.data.remote.dto.TorBoxUser
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import javax.inject.Inject
import javax.inject.Singleton

sealed class StreamState {
    object Idle : StreamState()
    data class Queuing(val name: String) : StreamState()
    data class Preparing(val name: String, val progress: Float) : StreamState()
    data class Ready(val streamUrl: String, val torrentItem: TorBoxTorrentItem, val file: TorBoxFile) : StreamState()
    data class ReadyAlbum(
        val tracks: List<AlbumTrack>,
        val torrentItem: TorBoxTorrentItem,
    ) : StreamState()
    data class Error(val message: String) : StreamState()
}

data class AlbumTrack(
    val url: String,
    val file: TorBoxFile,
)

@Singleton
class TorBoxRepository @Inject constructor(
    private val api: TorBoxApi,
    private val settingsStore: SettingsStore,
    private val authInterceptor: TorBoxAuthInterceptor,
) {
    init {
        // Kept intentionally empty — key synced via syncApiKey()
    }

    suspend fun syncApiKey() {
        val key = settingsStore.torBoxApiKey.first()
        authInterceptor.apiKey = key
    }

    suspend fun search(query: String): Result<List<TorBoxSearchResult>> = runCatching {
        syncApiKey()
        val resp = api.search(query)
        if (!resp.success) error(resp.detail ?: resp.error ?: "Search failed")
        (resp.data ?: emptyList()).sortedWith(
            compareByDescending<TorBoxSearchResult> { it.seeders }
                .thenByDescending { it.score }
        )
    }

    suspend fun validateApiKey(): Result<TorBoxUser> = runCatching {
        val resp = api.getUserInfo()
        if (!resp.success) error(resp.detail ?: resp.error ?: "Invalid API key")
        resp.data ?: error("No user data")
    }

    fun streamResult(result: TorBoxSearchResult): Flow<StreamState> = flow {
        emit(StreamState.Queuing(result.name))
        syncApiKey()
        val apiKey = authInterceptor.apiKey

        val torrentId = addOrFindTorrent(result)

        val ready = pollUntilReady(torrentId) { state -> emit(state) }

        // Pick best audio file (prefer FLAC, then by size desc)
        val audioFiles = ready.files?.filter { it.isAudio } ?: emptyList()
        if (audioFiles.isEmpty()) error("No audio files found in this torrent")
        val bestFile = audioFiles.maxWithOrNull(
            compareBy<TorBoxFile> { if (it.isFlac) 1 else 0 }
                .thenByDescending { it.size }
        )!!

        val dlResp = api.requestDownload(
            token = apiKey,
            torrentId = ready.id,
            fileId = bestFile.id,
        )
        if (!dlResp.success) error(dlResp.detail ?: dlResp.error ?: "Failed to get download link")
        val url = dlResp.data ?: error("Empty download URL")

        emit(StreamState.Ready(url, ready, bestFile))
    }

    fun streamAlbum(result: TorBoxSearchResult): Flow<StreamState> = flow {
        emit(StreamState.Queuing(result.name))
        syncApiKey()
        val apiKey = authInterceptor.apiKey

        val torrentId = addOrFindTorrent(result)

        val ready = pollUntilReady(torrentId) { state -> emit(state) }

        val audioFiles = (ready.files ?: emptyList())
            .filter { it.isAudio }
            .sortedWith(
                compareByDescending<TorBoxFile> { if (it.isFlac) 1 else 0 }
                    .thenBy { it.name }
            )

        if (audioFiles.isEmpty()) error("No audio files found")

        // Resolve stream URLs for all tracks
        val tracks = audioFiles.mapNotNull { file ->
            val dlResp = api.requestDownload(
                token = apiKey,
                torrentId = ready.id,
                fileId = file.id,
            )
            if (dlResp.success) dlResp.data?.let { url -> AlbumTrack(url, file) }
            else null
        }

        if (tracks.isEmpty()) error("Could not resolve stream URLs for any track")

        emit(StreamState.ReadyAlbum(tracks, ready))
    }

    private suspend fun addOrFindTorrent(result: TorBoxSearchResult): Long {
        val createResp = api.addMagnet(result.magnet)
        return when {
            createResp.success -> createResp.data?.torrentId
            createResp.detail?.contains("already", ignoreCase = true) == true ->
                findTorrentByHash(result.hash)?.id
            else -> error(createResp.detail ?: createResp.error ?: "Failed to add torrent")
        } ?: error("Could not resolve torrent ID")
    }

    private suspend fun pollUntilReady(
        torrentId: Long,
        onProgress: suspend (StreamState) -> Unit,
    ): TorBoxTorrentItem {
        var delayMs = 2_000L
        for (attempt in 0 until 30) {
            val listResp = api.listTorrents(bypassCache = true)
            val found = listResp.data?.firstOrNull { it.id == torrentId }
            when {
                found == null -> { /* not indexed yet */ }
                found.isFailed -> error("Torrent failed: ${found.status}")
                found.isReady -> return found
                else -> onProgress(StreamState.Preparing(found.name, found.progress))
            }
            delay(delayMs)
            if (attempt >= 2) delayMs = (delayMs * 1.5).toLong().coerceAtMost(10_000L)
        }
        error("Torrent did not become ready in time")
    }

    private suspend fun findTorrentByHash(hash: String): TorBoxTorrentItem? {
        val listResp = api.listTorrents(bypassCache = true)
        return listResp.data?.firstOrNull {
            it.hash?.equals(hash, ignoreCase = true) == true
        }
    }
}
