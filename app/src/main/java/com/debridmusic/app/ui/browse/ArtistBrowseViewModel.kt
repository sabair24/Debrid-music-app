package com.debridmusic.app.ui.browse

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.data.repository.BrowseRepository
import com.debridmusic.app.domain.model.ArtistDiscography
import com.debridmusic.app.domain.model.BrowseTrack
import com.debridmusic.app.player.BrowsePlayer
import com.debridmusic.app.player.PlayerController
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ArtistBrowseUiState(
    val discography: ArtistDiscography? = null,
    val isLoading: Boolean = true,
    val sourcePicker: SourcePickerState? = null,
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

    private var resolveJob: Job? = null

    init {
        viewModelScope.launch {
            val disco = browseRepository.artistDiscography(artistId)
            _state.update { it.copy(discography = disco, isLoading = false) }
        }
    }

    // Tapping a top song shows its torrent sources (Stremio-style).
    fun showSourcesForTrack(track: BrowseTrack) {
        _state.update {
            it.copy(sourcePicker = SourcePickerState(
                title = track.title, artist = track.artist, album = track.album, matchSong = track.title,
            ))
        }
        viewModelScope.launch {
            val sources = browsePlayer.findSources(track.artist, track.album, track.title)
            _state.update { st -> st.sourcePicker?.let { st.copy(sourcePicker = it.copy(loading = false, sources = sources)) } ?: st }
        }
    }

    fun pickSource(result: TorBoxSearchResult) {
        val picker = _state.value.sourcePicker ?: return
        _state.update { it.copy(sourcePicker = picker.copy(resolvingHash = result.hash, message = "Voorbereiden…")) }
        resolveJob?.cancel()
        resolveJob = viewModelScope.launch {
            val progress: (String) -> Unit = { msg ->
                _state.update { st -> st.sourcePicker?.let { st.copy(sourcePicker = it.copy(message = msg)) } ?: st }
            }
            var r = browsePlayer.playResult(result, picker.artist, picker.album, picker.matchSong, picker.shuffle, progress)
            // If the picked source fails/stalls, auto-fall back to another playable
            // source (skipping the one that just failed) instead of leaving the user stuck.
            if (r.isFailure) {
                ensureActive()
                progress("Andere bron proberen…")
                val exclude = setOfNotNull(result.hash.takeIf { it.isNotBlank() }?.lowercase())
                r = if (picker.matchSong != null) {
                    browsePlayer.playSong(picker.artist, picker.album, picker.matchSong, exclude, progress)
                } else {
                    browsePlayer.playAlbum(picker.artist, picker.album, picker.shuffle, exclude, progress)
                }
            }
            // If another source was picked meanwhile this job is cancelled — don't
            // overwrite the new pick's status with a stale result.
            ensureActive()
            _state.update { st ->
                if (r.isSuccess) st.copy(sourcePicker = null)
                else st.sourcePicker?.let { st.copy(sourcePicker = it.copy(resolvingHash = null, message = "Geen werkende bron — probeer een andere")) } ?: st
            }
        }
    }

    fun dismissSources() {
        resolveJob?.cancel()
        _state.update { it.copy(sourcePicker = null) }
    }
}
