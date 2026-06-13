package com.debridmusic.app.ui.artist

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.repository.MusicRepository
import com.debridmusic.app.domain.model.Album
import com.debridmusic.app.domain.model.Artist
import com.debridmusic.app.domain.model.Track
import com.debridmusic.app.metadata.MetadataEnricher.ArtistMatch
import com.debridmusic.app.player.PlayerController
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ArtistDetailUiState(
    val artist: Artist? = null,
    val albums: List<Album> = emptyList(),
    val tracks: List<Track> = emptyList(),
    val isLoading: Boolean = true,
    val showFullBio: Boolean = false,
    val editorOpen: Boolean = false,
    val searching: Boolean = false,
    val candidates: List<ArtistMatch> = emptyList(),
    val refreshing: Boolean = false,
)

@HiltViewModel
class ArtistDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repository: MusicRepository,
    val playerController: PlayerController,
) : ViewModel() {

    private val artistId: Long = checkNotNull(savedStateHandle["artistId"])

    private val _state = MutableStateFlow(ArtistDetailUiState())
    val state: StateFlow<ArtistDetailUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            repository.observeTracksByArtist(artistId).collect { tracks ->
                _state.update { it.copy(tracks = tracks, isLoading = false) }
            }
        }
        viewModelScope.launch {
            repository.observeAlbums().collect { all ->
                _state.update { it.copy(albums = all.filter { a -> a.artistId == artistId }) }
            }
        }
        viewModelScope.launch {
            val artist = repository.getArtist(artistId)
            _state.update { it.copy(artist = artist) }
        }
    }

    fun playAll() {
        val tracks = _state.value.tracks
        if (tracks.isNotEmpty()) playerController.playQueue(tracks, 0)
    }

    fun playTrack(track: Track) {
        val queue = _state.value.tracks
        val idx = queue.indexOfFirst { it.id == track.id }.coerceAtLeast(0)
        playerController.playQueue(queue, idx)
    }

    fun toggleBio() = _state.update { it.copy(showFullBio = !it.showFullBio) }

    // ── Manual metadata search ──────────────────────────────────────────────────
    fun openEditor() {
        _state.update { it.copy(editorOpen = true) }
        searchMetadata(_state.value.artist?.name.orEmpty())
    }

    fun closeEditor() = _state.update { it.copy(editorOpen = false) }

    fun searchMetadata(query: String) {
        if (query.isBlank()) return
        _state.update { it.copy(searching = true) }
        viewModelScope.launch {
            val results = repository.searchArtistMetadata(query)
            _state.update { it.copy(candidates = results, searching = false) }
        }
    }

    fun applyMatch(match: ArtistMatch) {
        viewModelScope.launch {
            _state.update { it.copy(editorOpen = false, refreshing = true) }
            repository.applyArtistMetadata(artistId, match)
            _state.update { it.copy(artist = repository.getArtist(artistId), refreshing = false) }
        }
    }

    fun reEnrich() {
        viewModelScope.launch {
            _state.update { it.copy(refreshing = true) }
            repository.reEnrichArtist(artistId)
            _state.update { it.copy(artist = repository.getArtist(artistId), refreshing = false) }
        }
    }
}
