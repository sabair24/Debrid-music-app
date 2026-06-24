package com.debridmusic.app.torbox

import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.remote.api.TorBoxApi
import com.debridmusic.app.data.remote.dto.TorBoxFile
import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.data.remote.dto.TorBoxTorrentItem
import com.debridmusic.app.data.remote.dto.TorBoxUser
import com.debridmusic.app.search.SearchAggregator
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
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
    data class TrackList(
        val files: List<TorBoxFile>,
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
    private val searchAggregator: SearchAggregator,
    private val settingsStore: SettingsStore,
    private val authInterceptor: TorBoxAuthInterceptor,
) {
    suspend fun syncApiKey() {
        val key = settingsStore.torBoxApiKey.first()
        authInterceptor.apiKey = key
    }

    // Aggregates all enabled torrent sources (Pirate Bay, BitSearch, Knaben, …),
    // deduped + sorted by seeders. Resolution to a stream still goes via TorBox.
    suspend fun search(query: String): Result<List<TorBoxSearchResult>> = runCatching {
        searchAggregator.search(query)
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

        val torrentRef = addOrFindTorrent(result)
        val ready = pollUntilReady(torrentRef) { state -> emit(state) }

        val audioFiles = ready.files?.filter { it.isAudio } ?: emptyList()
        if (audioFiles.isEmpty()) error("No audio files found in this torrent")
        val bestFile = audioFiles.maxWith(
            compareBy<TorBoxFile> { if (it.isFlac) 1 else 0 }.thenByDescending { it.size }
        )

        val dlResp = api.requestDownload(token = apiKey, torrentId = ready.id, fileId = bestFile.id)
        if (!dlResp.success) error(dlResp.detail ?: dlResp.error ?: "Failed to get download link")
        val url = dlResp.data ?: error("Empty download URL")

        emit(StreamState.Ready(url, ready, bestFile))
    }.catch { e -> emit(StreamState.Error(e.message ?: "Stream failed")) }

    fun streamAlbum(result: TorBoxSearchResult): Flow<StreamState> = flow {
        emit(StreamState.Queuing(result.name))
        syncApiKey()
        val apiKey = authInterceptor.apiKey

        val torrentRef = addOrFindTorrent(result)
        val ready = pollUntilReady(torrentRef) { state -> emit(state) }

        val audioFiles = (ready.files ?: emptyList())
            .filter { it.isAudio }
            .sortedWith(
                compareByDescending<TorBoxFile> { if (it.isFlac) 1 else 0 }.thenBy { it.name }
            )
        if (audioFiles.isEmpty()) error("No audio files found")

        val tracks = audioFiles.mapNotNull { file ->
            val dlResp = api.requestDownload(token = apiKey, torrentId = ready.id, fileId = file.id)
            if (dlResp.success) dlResp.data?.let { url -> AlbumTrack(url, file) } else null
        }
        if (tracks.isEmpty()) error("Could not resolve stream URLs for any track")

        emit(StreamState.ReadyAlbum(tracks, ready))
    }.catch { e -> emit(StreamState.Error(e.message ?: "Album stream failed")) }

    fun streamTrackPicker(result: TorBoxSearchResult): Flow<StreamState> = flow {
        emit(StreamState.Queuing(result.name))
        syncApiKey()

        val torrentRef = addOrFindTorrent(result)
        val ready = pollUntilReady(torrentRef) { state -> emit(state) }

        val audioFiles = (ready.files ?: emptyList())
            .filter { it.isAudio }
            .sortedWith(
                compareByDescending<TorBoxFile> { if (it.isFlac) 1 else 0 }.thenBy { it.name }
            )
        if (audioFiles.isEmpty()) error("No audio files found")

        emit(StreamState.TrackList(audioFiles, ready))
    }.catch { e -> emit(StreamState.Error(e.message ?: "Failed to load tracks")) }

    suspend fun resolveTrackUrl(torrentItem: TorBoxTorrentItem, file: TorBoxFile): String {
        syncApiKey()
        val apiKey = authInterceptor.apiKey
        val dlResp = api.requestDownload(token = apiKey, torrentId = torrentItem.id, fileId = file.id)
        if (!dlResp.success) error(dlResp.detail ?: dlResp.error ?: "Failed to get download link")
        return dlResp.data ?: error("Empty download URL")
    }

    // Identifies an added torrent for polling. `id` may be null while a non-cached
    // torrent sits in the queue (no torrent_id yet) — in that window it can only be
    // matched by its infohash, so we always carry the hash too.
    private data class TorrentRef(val id: Long?, val hash: String)

    private suspend fun addOrFindTorrent(result: TorBoxSearchResult): TorrentRef {
        val createResp = api.addMagnet(result.magnet)
        // Prefer the canonical hash TorBox parsed from the magnet; fall back to ours.
        val hash = createResp.data?.hash?.takeIf { it.isNotBlank() } ?: result.hash
        if (hash.isBlank()) error("Torrent has no infohash")
        return when {
            // Cached torrents return a real torrent_id; queued ones don't (→ 0), and are
            // tracked by hash until they appear in the list. Either way we can proceed.
            createResp.success -> TorrentRef(createResp.data?.torrentId?.takeIf { it > 0 }, hash)
            createResp.detail?.contains("already", ignoreCase = true) == true ->
                TorrentRef(findTorrentByHash(hash)?.id, hash)
            createResp.error?.contains("already", ignoreCase = true) == true ->
                TorrentRef(findTorrentByHash(hash)?.id, hash)
            else -> error(createResp.detail ?: createResp.error ?: "Failed to add torrent")
        }
    }

    private suspend fun pollUntilReady(
        ref: TorrentRef,
        onProgress: suspend (StreamState) -> Unit,
    ): TorBoxTorrentItem {
        var delayMs = 2_000L
        for (attempt in 0 until 30) {
            val listResp = api.listTorrents(bypassCache = true)
            val found = listResp.data?.firstOrNull { item ->
                (ref.id != null && item.id == ref.id) ||
                    item.hash?.equals(ref.hash, ignoreCase = true) == true
            }
            when {
                found == null -> { /* not indexed yet */ }
                found.isFailed -> error("Torrent failed: ${found.status}")
                found.isReady && found.files?.any { it.isAudio } == true -> return found
                found.isReady -> { /* ready but files list not yet populated — keep polling */ }
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
