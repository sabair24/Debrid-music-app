package com.debridmusic.app.ui.browse

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.repository.BrowseRepository
import com.debridmusic.app.domain.model.ArtistDiscography
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

data class ArtistBrowseUiState(
    val discography: ArtistDiscography? = null,
    val isLoading: Boolean = true,
    val resolving: Boolean = false,
    val statusMessage: String? = null,
)

@HiltViewModel
class ArtistBrowseViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val browseRepository: BrowseRepository,
    private val browsePlayer: BrowsePlayer,
    val playerController: PlayerController,
) : ViewModel() {

    private val artistId: Long = checkNotNull(savedStateHandle["deezerArtistId"])

    private val _state = MutableStateFlow(ArtistBrowseUiState())
    val state: StateFlow<ArtistBrowseUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            val disco = browseRepository.artistDiscography(artistId)
            _state.update { it.copy(discography = disco, isLoading = false) }
        }
    }

    fun playSong(track: BrowseTrack) {
        if (_state.value.resolving) return
        _state.update { it.copy(resolving = true, statusMessage = "Bron zoeken…") }
        viewModelScope.launch {
            val result = browsePlayer.playSong(track.artist, track.album, track.title) { msg ->
                _state.update { it.copy(statusMessage = msg) }
            }
            _state.update {
                it.copy(
                    resolving = false,
                    statusMessage = if (result.isFailure) "Geen bron voor \"${track.title}\"" else null,
                )
            }
        }
    }

    fun clearStatus() = _state.update { it.copy(statusMessage = null) }
}
