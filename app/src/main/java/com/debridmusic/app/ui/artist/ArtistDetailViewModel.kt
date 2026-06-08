package com.debridmusic.app.ui.artist

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.repository.MusicRepository
import com.debridmusic.app.domain.model.Album
import com.debridmusic.app.domain.model.Artist
import com.debridmusic.app.domain.model.Track
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
}
