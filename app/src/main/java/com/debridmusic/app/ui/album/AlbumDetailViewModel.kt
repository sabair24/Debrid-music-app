package com.debridmusic.app.ui.album

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.repository.MusicRepository
import com.debridmusic.app.domain.model.Album
import com.debridmusic.app.domain.model.Track
import com.debridmusic.app.player.PlayerController
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

data class AlbumDetailUiState(
    val album: Album? = null,
    val tracks: List<Track> = emptyList(),
    val isLoading: Boolean = true,
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
}
