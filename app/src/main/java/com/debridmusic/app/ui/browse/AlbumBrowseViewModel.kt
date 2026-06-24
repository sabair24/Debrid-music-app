package com.debridmusic.app.ui.browse

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.data.repository.BrowseRepository
import com.debridmusic.app.data.repository.MusicRepository
import com.debridmusic.app.domain.model.BrowseAlbum
import com.debridmusic.app.domain.model.BrowseTrack
import com.debridmusic.app.download.DownloadRequest
import com.debridmusic.app.download.OfflineDownloadManager
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

data class AlbumBrowseUiState(
    val album: BrowseAlbum? = null,
    val tracks: List<BrowseTrack> = emptyList(),
    val isLoading: Boolean = true,
    val sourcePicker: SourcePickerState? = null,
    val addStatus: String? = null,
    val addBusy: Boolean = false,
)

@HiltViewModel
class AlbumBrowseViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val browseRepository: BrowseRepository,
    private val browsePlayer: BrowsePlayer,
    private val musicRepository: MusicRepository,
    private val offlineDownloadManager: OfflineDownloadManager,
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
            // If the user picked another source meanwhile, this job was cancelled —
            // don't let a stale result overwrite the new pick's status.
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

    /** Save the album to the library as "online" tracks (re-resolved on play). */
    fun saveToLibrary() {
        val album = _state.value.album ?: return
        if (_state.value.addBusy) return
        _state.update { it.copy(addBusy = true, addStatus = "Bewaren…") }
        viewModelScope.launch {
            browsePlayer.resolveAlbum(album.artist, album.title) { msg -> _state.update { it.copy(addStatus = msg) } }
                .onSuccess { resolved ->
                    val n = musicRepository.addOnlineAlbum(
                        artistName = album.artist, albumTitle = album.title,
                        artworkUri = album.artworkUri, year = album.year, torrentHash = resolved.hash,
                        tracks = resolved.tracks.map {
                            MusicRepository.OnlineTrackInput(it.title, it.fileName, it.trackNumber, it.isFlac, it.sizeBytes)
                        },
                    )
                    _state.update { it.copy(addBusy = false, addStatus = "$n nummers bewaard in Bibliotheek") }
                }
                .onFailure { e -> _state.update { it.copy(addBusy = false, addStatus = "Bewaren mislukt: ${e.message}") } }
        }
    }

    /** Download the album to the device and add it to the library as local tracks. */
    fun downloadToLibrary() {
        val album = _state.value.album ?: return
        if (_state.value.addBusy) return
        _state.update { it.copy(addBusy = true, addStatus = "Bron zoeken…") }
        viewModelScope.launch {
            browsePlayer.resolveAlbum(album.artist, album.title) { msg -> _state.update { it.copy(addStatus = msg) } }
                .onSuccess { resolved ->
                    offlineDownloadManager.enqueueAll(
                        resolved.tracks.map { t ->
                            DownloadRequest(
                                title = t.title, artist = album.artist, album = album.title,
                                sourceUrl = t.url, artworkUri = album.artworkUri, addToLibrary = true,
                            )
                        },
                    )
                    _state.update { it.copy(addBusy = false, addStatus = "${resolved.tracks.size} nummers downloaden → Bibliotheek") }
                }
                .onFailure { e -> _state.update { it.copy(addBusy = false, addStatus = "Download mislukt: ${e.message}") } }
        }
    }

    fun clearAddStatus() = _state.update { it.copy(addStatus = null) }

    private fun albumTitle(): String = _state.value.album?.title.orEmpty()
}
