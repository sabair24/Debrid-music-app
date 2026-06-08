package com.debridmusic.app.ui.library

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.repository.MusicRepository
import com.debridmusic.app.domain.model.Album
import com.debridmusic.app.domain.model.Artist
import com.debridmusic.app.domain.model.Track
import com.debridmusic.app.player.PlayerController
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

enum class LibraryTab { TRACKS, ALBUMS, ARTISTS }

data class LibraryUiState(
    val tab: LibraryTab = LibraryTab.TRACKS,
    val tracks: List<Track> = emptyList(),
    val albums: List<Album> = emptyList(),
    val artists: List<Artist> = emptyList(),
    val searchQuery: String = "",
    val searchResults: List<Track> = emptyList(),
    val isSearching: Boolean = false,
    val isScanning: Boolean = false,
    val scanMessage: String? = null,
    val totalTracks: Int = 0,
)

@HiltViewModel
class LibraryViewModel @Inject constructor(
    private val repository: MusicRepository,
    val playerController: PlayerController,
) : ViewModel() {

    private val _state = MutableStateFlow(LibraryUiState())
    val state: StateFlow<LibraryUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            repository.observeTracks().collect { tracks ->
                _state.update { it.copy(tracks = tracks) }
            }
        }
        viewModelScope.launch {
            repository.observeAlbums().collect { albums ->
                _state.update { it.copy(albums = albums) }
            }
        }
        viewModelScope.launch {
            repository.observeArtists().collect { artists ->
                _state.update { it.copy(artists = artists) }
            }
        }
        viewModelScope.launch {
            repository.trackCount().collect { count ->
                _state.update { it.copy(totalTracks = count) }
            }
        }
    }

    fun setTab(tab: LibraryTab) { _state.update { it.copy(tab = tab) } }

    fun setSearchQuery(query: String) {
        _state.update { it.copy(searchQuery = query, isSearching = query.isNotBlank()) }
        if (query.isNotBlank()) {
            viewModelScope.launch {
                val results = repository.search(query)
                _state.update { it.copy(searchResults = results) }
            }
        }
    }

    fun clearSearch() {
        _state.update { it.copy(searchQuery = "", isSearching = false, searchResults = emptyList()) }
    }

    fun scanLocalMedia() {
        if (_state.value.isScanning) return
        _state.update { it.copy(isScanning = true, scanMessage = null) }
        viewModelScope.launch {
            val count = repository.scanLocalMedia()
            _state.update {
                it.copy(
                    isScanning = false,
                    scanMessage = if (count > 0) "Imported $count new tracks" else "No new tracks found",
                )
            }
        }
    }

    fun playTrack(track: Track, queue: List<Track>? = null) {
        val tracks = queue ?: _state.value.tracks
        val index = tracks.indexOfFirst { it.id == track.id }.coerceAtLeast(0)
        playerController.playQueue(tracks, index)
    }

    fun playAlbum(album: Album) {
        viewModelScope.launch {
            val tracks = repository.observeTracksByAlbum(album.id).first()
            if (tracks.isNotEmpty()) playerController.playQueue(tracks, 0)
        }
    }
}
