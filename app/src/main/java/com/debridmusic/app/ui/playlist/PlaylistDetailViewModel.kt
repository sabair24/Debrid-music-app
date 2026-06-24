package com.debridmusic.app.ui.playlist

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.repository.MusicRepository
import com.debridmusic.app.domain.model.Track
import com.debridmusic.app.player.PlayerController
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

data class PlaylistDetailUiState(
    val playlistName: String = "",
    val tracks: List<Track> = emptyList(),
)

@HiltViewModel
class PlaylistDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val repository: MusicRepository,
    private val libraryPlayer: com.debridmusic.app.player.LibraryPlayer,
    val playerController: PlayerController,
) : ViewModel() {

    private val playlistId: Long = checkNotNull(savedStateHandle["playlistId"])

    private val _state = MutableStateFlow(PlaylistDetailUiState())
    val state: StateFlow<PlaylistDetailUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            repository.observePlaylistTracks(playlistId).collect { tracks ->
                _state.update { it.copy(tracks = tracks) }
            }
        }
        viewModelScope.launch {
            repository.observePlaylists().collect { playlists ->
                val name = playlists.find { it.id == playlistId }?.name ?: ""
                _state.update { it.copy(playlistName = name) }
            }
        }
    }

    fun playAll() {
        val tracks = _state.value.tracks
        if (tracks.isEmpty()) return
        viewModelScope.launch { libraryPlayer.play(tracks, 0) }
    }

    fun playTrack(track: Track) {
        val tracks = _state.value.tracks
        val index = tracks.indexOfFirst { it.id == track.id }.coerceAtLeast(0)
        viewModelScope.launch { libraryPlayer.play(tracks, index) }
    }

    fun removeTrack(trackId: Long) {
        viewModelScope.launch { repository.removeTrackFromPlaylist(playlistId, trackId) }
    }
}
