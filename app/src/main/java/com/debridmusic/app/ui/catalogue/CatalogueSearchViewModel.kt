package com.debridmusic.app.ui.catalogue

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.remote.dto.TorBoxFile
import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.data.remote.dto.TorBoxTorrentItem
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
    val streamingId: String? = null,   // hash of the item being streamed
    val streamState: StreamState = StreamState.Idle,
)

@HiltViewModel
class CatalogueSearchViewModel @Inject constructor(
    private val torBoxRepository: TorBoxRepository,
    val playerController: PlayerController,
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
                if (state is StreamState.Ready) {
                    playStreamUrl(state)
                }
            }
        }
    }

    fun cancelStream() {
        streamJob?.cancel()
        _state.update { it.copy(streamingId = null, streamState = StreamState.Idle) }
    }

    private fun playStreamUrl(ready: StreamState.Ready) {
        // Build a synthetic Track and play it via ExoPlayer
        playerController.playRemoteUrl(
            url = ready.streamUrl,
            title = ready.file.shortName ?: ready.file.name,
            artist = extractArtistFromName(ready.torrentItem.name),
            album = ready.torrentItem.name,
        )
    }

    private fun extractArtistFromName(torrentName: String): String {
        // Try "Artist - Album" pattern
        val dash = torrentName.indexOf(" - ")
        return if (dash > 0) torrentName.substring(0, dash).trim() else torrentName
    }
}
