package com.debridmusic.app.ui.catalogue

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.remote.dto.TorBoxFile
import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.data.remote.dto.TorBoxTorrentItem
import com.debridmusic.app.domain.model.Track
import com.debridmusic.app.download.OfflineDownloadManager
import com.debridmusic.app.metadata.StreamArtworkResolver
import com.debridmusic.app.player.PlayerController
import com.debridmusic.app.torbox.StreamState
import com.debridmusic.app.torbox.TorBoxRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

data class CatalogueSearchUiState(
    val query: String = "",
    val results: List<TorBoxSearchResult> = emptyList(),
    val isSearching: Boolean = false,
    val searchError: String? = null,
    val streamingId: String? = null,
    val streamState: StreamState = StreamState.Idle,
    val downloadingHash: String? = null,
)

@HiltViewModel
class CatalogueSearchViewModel @Inject constructor(
    private val torBoxRepository: TorBoxRepository,
    val playerController: PlayerController,
    private val offlineDownloadManager: OfflineDownloadManager,
    private val artworkResolver: StreamArtworkResolver,
) : ViewModel() {

    private val _state = MutableStateFlow(CatalogueSearchUiState())
    val state: StateFlow<CatalogueSearchUiState> = _state.asStateFlow()

    private var streamJob: Job? = null

    fun setQuery(q: String) = _state.update { it.copy(query = q, searchError = null) }

    fun search() {
        val query = _state.value.query.trim()
        if (query.isBlank()) return
        _state.update { it.copy(isSearching = true, results = emptyList(), searchError = null) }
        viewModelScope.launch {
            torBoxRepository.search(query)
                .onSuccess { results ->
                    _state.update { it.copy(isSearching = false, results = results) }
                }
                .onFailure { e ->
                    _state.update { it.copy(isSearching = false, searchError = e.message) }
                }
        }
    }

    fun stream(result: TorBoxSearchResult, albumMode: Boolean = false) {
        if (_state.value.streamingId == result.hash) return
        streamJob?.cancel()
        _state.update { it.copy(streamingId = result.hash, streamState = StreamState.Idle) }

        streamJob = viewModelScope.launch {
            val flow = if (albumMode) torBoxRepository.streamAlbum(result)
            else torBoxRepository.streamResult(result)

            flow.collect { state ->
                _state.update { it.copy(streamState = state) }
                when (state) {
                    is StreamState.Ready -> playStreamUrl(state)
                    is StreamState.ReadyAlbum -> playAlbumQueue(state)
                    else -> {}
                }
            }
        }
    }

    fun streamTrackPicker(result: TorBoxSearchResult) {
        if (_state.value.streamingId == result.hash) return
        streamJob?.cancel()
        _state.update { it.copy(streamingId = result.hash, streamState = StreamState.Idle) }

        streamJob = viewModelScope.launch {
            torBoxRepository.streamTrackPicker(result).collect { state ->
                _state.update { it.copy(streamState = state) }
            }
        }
    }

    fun playSelectedTrack(torrentItem: com.debridmusic.app.data.remote.dto.TorBoxTorrentItem, file: TorBoxFile) {
        viewModelScope.launch {
            val result = runCatching { torBoxRepository.resolveTrackUrl(torrentItem, file) }
            result.onSuccess { url ->
                val ready = StreamState.Ready(url, torrentItem, file)
                _state.update { it.copy(streamState = ready) }
                playStreamUrl(ready)
            }.onFailure { e ->
                _state.update { it.copy(streamState = StreamState.Error(e.message ?: "Failed to resolve URL")) }
            }
        }
    }

    fun cancelStream() {
        streamJob?.cancel()
        _state.update { it.copy(streamingId = null, streamState = StreamState.Idle) }
    }

    private suspend fun playStreamUrl(ready: StreamState.Ready) {
        val title = ready.file.shortName ?: ready.file.name
        val artist = extractArtistFromName(ready.torrentItem.name)
        val album = ready.torrentItem.name
        playerController.playRemoteUrl(
            url = ready.streamUrl,
            title = title,
            artist = artist,
            album = album,
            artworkUri = artworkResolver.resolve(artist, title, album),
        )
    }

    private suspend fun playAlbumQueue(ready: StreamState.ReadyAlbum) {
        val albumName = ready.torrentItem.name
        val artist = extractArtistFromName(albumName)
        val art = artworkResolver.resolve(artist, albumName, albumName)
        val tracks = ready.tracks.mapIndexed { index, albumTrack ->
            Track(
                id = -(index + 1L),
                title = albumTrack.file.shortName ?: albumTrack.file.name,
                artistName = artist,
                albumTitle = albumName,
                albumId = -1L,
                artistId = -1L,
                uri = albumTrack.url,
                durationMs = 0L,
                trackNumber = index + 1,
                discNumber = 1,
                year = null,
                artworkUri = art,
                genre = null,
                bitrate = null,
                sampleRate = null,
                isLossless = albumTrack.file.isFlac,
                fileSize = albumTrack.file.size,
                dateAdded = System.currentTimeMillis(),
            )
        }
        playerController.playQueue(tracks)
    }

    fun downloadCurrentStream() {
        val ready = _state.value.streamState as? StreamState.Ready ?: return
        val hash = _state.value.streamingId ?: return
        _state.update { it.copy(downloadingHash = hash) }
        viewModelScope.launch {
            val title = ready.file.shortName ?: ready.file.name
            val artist = extractArtistFromName(ready.torrentItem.name)
            val album = ready.torrentItem.name
            offlineDownloadManager.startDownload(
                title = title,
                artist = artist,
                album = album,
                sourceUrl = ready.streamUrl,
                artworkUri = artworkResolver.resolve(artist, title, album),
            ).collect { status ->
                if (status.name == "DONE" || status.name == "FAILED") {
                    _state.update { it.copy(downloadingHash = null) }
                }
            }
        }
    }

    private fun extractArtistFromName(torrentName: String): String {
        val dash = torrentName.indexOf(" - ")
        return if (dash > 0) torrentName.substring(0, dash).trim() else torrentName
    }
}
