package com.debridmusic.app.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.repository.MusicRepository
import com.debridmusic.app.domain.model.Album
import com.debridmusic.app.domain.model.Artist
import com.debridmusic.app.domain.model.Track
import com.debridmusic.app.player.PlayerController
import dagger.hilt.android.lifecycle.HiltViewModel
import com.debridmusic.app.player.LibraryPlayer
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

data class HomeUiState(
    val recentTracks: List<Track> = emptyList(),
    val albums: List<Album> = emptyList(),
    val artists: List<Artist> = emptyList(),
)

@HiltViewModel
class HomeViewModel @Inject constructor(
    private val repository: MusicRepository,
    private val libraryPlayer: LibraryPlayer,
    val playerController: PlayerController,
) : ViewModel() {

    val recentTracks: StateFlow<List<Track>> = repository.observeRecentlyAdded(24)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
    val albums: StateFlow<List<Album>> = repository.observeAlbums()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
    val artists: StateFlow<List<Artist>> = repository.observeArtists()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun playTrack(track: Track, queue: List<Track>) {
        val index = queue.indexOfFirst { it.id == track.id }.coerceAtLeast(0)
        viewModelScope.launch { libraryPlayer.play(queue, index) }
    }
}
