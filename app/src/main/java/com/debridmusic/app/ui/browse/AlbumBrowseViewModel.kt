package com.debridmusic.app.ui.browse

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.repository.BrowseRepository
import com.debridmusic.app.domain.model.BrowseAlbum
import com.debridmusic.app.domain.model.BrowseTrack
import com.debridmusic.app.player.BrowsePlayer
import com.debridmusic.app.player.PlayerController
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class AlbumBrowseUiState(
    val album: BrowseAlbum? = null,
    val tracks: List<BrowseTrack> = emptyList(),
    val isLoading: Boolean = true,
    val resolving: Boolean = false,
    val statusMessage: String? = null,
)

@HiltViewModel
class AlbumBrowseViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val browseRepository: BrowseRepository,
    private val browsePlayer: BrowsePlayer,
    val playerController: PlayerController,
) : ViewModel() {

    private val albumId: Long = checkNotNull(savedStateHandle["deezerAlbumId"])

    private val _state = MutableStateFlow(AlbumBrowseUiState())
    val state: StateFlow<AlbumBrowseUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            val (album, tracks) = browseRepository.albumWithTracks(albumId)
            _state.update { it.copy(album = album, tracks = tracks, isLoading = false) }
        }
    }

    fun playTrack(track: BrowseTrack) = resolve("Bron zoeken…", "Geen bron voor \"${track.title}\"") {
        browsePlayer.playSong(track.artist, track.album.ifBlank { albumTitle() }, track.title, it)
    }

    fun playAlbum(shuffle: Boolean) {
        val album = _state.value.album ?: return
        resolve(
            progress = if (shuffle) "Shuffle voorbereiden…" else "Album voorbereiden…",
            failure = "Geen bron voor dit album",
        ) { onProgress -> browsePlayer.playAlbum(album.artist, album.title, shuffle, onProgress) }
    }

    private fun albumTitle(): String = _state.value.album?.title.orEmpty()

    private fun resolve(
        progress: String,
        failure: String,
        block: suspend ((String) -> Unit) -> Result<Unit>,
    ) {
        if (_state.value.resolving) return
        _state.update { it.copy(resolving = true, statusMessage = progress) }
        viewModelScope.launch {
            val result = block { msg -> _state.update { it.copy(statusMessage = msg) } }
            _state.update {
                it.copy(resolving = false, statusMessage = if (result.isFailure) failure else null)
            }
        }
    }

    fun clearStatus() = _state.update { it.copy(statusMessage = null) }
}
