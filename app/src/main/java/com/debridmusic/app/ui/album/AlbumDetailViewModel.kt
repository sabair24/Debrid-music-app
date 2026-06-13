package com.debridmusic.app.ui.album

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.repository.MusicRepository
import com.debridmusic.app.domain.model.Album
import com.debridmusic.app.domain.model.Track
import com.debridmusic.app.metadata.MetadataEnricher.AlbumMatch
import com.debridmusic.app.player.PlayerController
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

data class AlbumDetailUiState(
    val album: Album? = null,
    val tracks: List<Track> = emptyList(),
    val isLoading: Boolean = true,
    val editorOpen: Boolean = false,
    val searching: Boolean = false,
    val candidates: List<AlbumMatch> = emptyList(),
    val refreshing: Boolean = false,
)

@HiltViewModel
class AlbumDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repository: MusicRepository,
    val playerController: PlayerController,
) : ViewModel() {

    private val albumId: Long = checkNotNull(savedStateHandle["albumId"])

    private val _state = MutableStateFlow(AlbumDetailUiState())
    val state: StateFlow<AlbumDetailUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            repository.observeTracksByAlbum(albumId).collect { tracks ->
                _state.update { it.copy(tracks = tracks, isLoading = false) }
            }
        }
        viewModelScope.launch {
            val album = repository.getAlbum(albumId)
            _state.update { it.copy(album = album) }
        }
    }

    fun playTrack(track: Track) {
        val queue = _state.value.tracks
        val index = queue.indexOfFirst { it.id == track.id }.coerceAtLeast(0)
        playerController.playQueue(queue, index)
    }

    fun playAll() {
        val tracks = _state.value.tracks
        if (tracks.isNotEmpty()) playerController.playQueue(tracks, 0)
    }

    // ── Manual metadata search ──────────────────────────────────────────────────
    fun openEditor() {
        _state.update { it.copy(editorOpen = true) }
        val a = _state.value.album
        searchMetadata(listOfNotNull(a?.title, a?.artistName).joinToString(" "))
    }

    fun closeEditor() = _state.update { it.copy(editorOpen = false) }

    fun searchMetadata(query: String) {
        if (query.isBlank()) return
        _state.update { it.copy(searching = true) }
        viewModelScope.launch {
            val results = repository.searchAlbumMetadata(query)
            _state.update { it.copy(candidates = results, searching = false) }
        }
    }

    fun applyMatch(match: AlbumMatch) {
        viewModelScope.launch {
            _state.update { it.copy(editorOpen = false, refreshing = true) }
            repository.applyAlbumMetadata(albumId, match)
            _state.update { it.copy(album = repository.getAlbum(albumId), refreshing = false) }
        }
    }

    fun reEnrich() {
        viewModelScope.launch {
            _state.update { it.copy(refreshing = true) }
            repository.reEnrichAlbum(albumId)
            _state.update { it.copy(album = repository.getAlbum(albumId), refreshing = false) }
        }
    }
}
