package com.debridmusic.app.ui.browse

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.data.repository.BrowseRepository
import com.debridmusic.app.domain.model.BrowseAlbum
import com.debridmusic.app.domain.model.BrowseTrack
import com.debridmusic.app.player.BrowsePlayer
import com.debridmusic.app.player.PlayerController
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
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
    val sourcePicker: SourcePickerState? = null,
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

    private var resolveJob: Job? = null

    init {
        viewModelScope.launch {
            val (album, tracks) = browseRepository.albumWithTracks(albumId)
            _state.update { it.copy(album = album, tracks = tracks, isLoading = false) }
        }
    }

    // Tapping a track shows its torrent sources (Stremio-style); picking one plays
    // the album starting on that track.
    fun showSourcesForTrack(track: BrowseTrack) =
        openPicker(track.title, track.album.ifBlank { albumTitle() }, matchSong = track.title, shuffle = false)

    fun showAlbumSources(shuffle: Boolean) {
        val album = _state.value.album ?: return
        openPicker(album.title, album.title, matchSong = null, shuffle = shuffle)
    }

    private fun openPicker(title: String, albumForSearch: String, matchSong: String?, shuffle: Boolean) {
        val artist = _state.value.album?.artist.orEmpty()
        _state.update {
            it.copy(sourcePicker = SourcePickerState(title = title, artist = artist, album = albumForSearch, matchSong = matchSong, shuffle = shuffle))
        }
        viewModelScope.launch {
            val sources = browsePlayer.findSources(artist, albumForSearch, matchSong)
            _state.update { st -> st.sourcePicker?.let { st.copy(sourcePicker = it.copy(loading = false, sources = sources)) } ?: st }
        }
    }

    fun pickSource(result: TorBoxSearchResult) {
        val picker = _state.value.sourcePicker ?: return
        _state.update { it.copy(sourcePicker = picker.copy(resolvingHash = result.hash, message = "Voorbereiden…")) }
        resolveJob?.cancel()
        resolveJob = viewModelScope.launch {
            val r = browsePlayer.playResult(result, picker.artist, picker.album, picker.matchSong, picker.shuffle) { msg ->
                _state.update { st -> st.sourcePicker?.let { st.copy(sourcePicker = it.copy(message = msg)) } ?: st }
            }
            _state.update { st ->
                if (r.isSuccess) st.copy(sourcePicker = null)
                else st.sourcePicker?.let { st.copy(sourcePicker = it.copy(resolvingHash = null, message = "Bron mislukt — kies een andere")) } ?: st
            }
        }
    }

    fun dismissSources() {
        resolveJob?.cancel()
        _state.update { it.copy(sourcePicker = null) }
    }

    private fun albumTitle(): String = _state.value.album?.title.orEmpty()
}
