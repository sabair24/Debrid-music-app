package com.debridmusic.app.ui.library

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.repository.DiscogsRepository
import com.debridmusic.app.data.repository.MusicRepository
import com.debridmusic.app.domain.model.Album
import com.debridmusic.app.domain.model.Artist
import com.debridmusic.app.domain.model.Playlist
import com.debridmusic.app.domain.model.Track
import com.debridmusic.app.player.PlayerController
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

enum class LibraryTab { TRACKS, ALBUMS, ARTISTS, PLAYLISTS, DISCOGS }

data class LibraryUiState(
    val tab: LibraryTab = LibraryTab.TRACKS,
    val tracks: List<Track> = emptyList(),
    val albums: List<Album> = emptyList(),
    val artists: List<Artist> = emptyList(),
    val playlists: List<Playlist> = emptyList(),
    val discogsCollection: List<Album> = emptyList(),
    val searchQuery: String = "",
    val searchResults: List<Track> = emptyList(),
    val isSearching: Boolean = false,
    val isScanning: Boolean = false,
    val scanMessage: String? = null,
    val totalTracks: Int = 0,
    // Playlist create dialog
    val showCreatePlaylist: Boolean = false,
    val newPlaylistName: String = "",
    // Add-to-playlist dialog
    val addToPlaylistTrack: Track? = null,
)

@HiltViewModel
class LibraryViewModel @Inject constructor(
    private val repository: MusicRepository,
    private val discogsRepository: DiscogsRepository,
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
            repository.observePlaylists().collect { playlists ->
                _state.update { it.copy(playlists = playlists) }
            }
        }
        viewModelScope.launch {
            repository.trackCount().collect { count ->
                _state.update { it.copy(totalTracks = count) }
            }
        }
        viewModelScope.launch {
            discogsRepository.observeCollection().collect { albums ->
                _state.update { it.copy(discogsCollection = albums) }
            }
        }
    }

    fun setTab(tab: LibraryTab) = _state.update { it.copy(tab = tab) }

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

    // ── Playlist management ───────────────────────────────────────────────────
    fun showCreatePlaylist() = _state.update { it.copy(showCreatePlaylist = true, newPlaylistName = "") }
    fun hideCreatePlaylist() = _state.update { it.copy(showCreatePlaylist = false) }
    fun setNewPlaylistName(name: String) = _state.update { it.copy(newPlaylistName = name) }

    fun createPlaylist() {
        val name = _state.value.newPlaylistName.trim()
        if (name.isBlank()) return
        viewModelScope.launch {
            repository.createPlaylist(name)
            _state.update { it.copy(showCreatePlaylist = false) }
        }
    }

    fun deletePlaylist(id: Long) {
        viewModelScope.launch { repository.deletePlaylist(id) }
    }

    fun showAddToPlaylist(track: Track) = _state.update { it.copy(addToPlaylistTrack = track) }
    fun hideAddToPlaylist() = _state.update { it.copy(addToPlaylistTrack = null) }

    fun addTrackToPlaylist(playlistId: Long) {
        val track = _state.value.addToPlaylistTrack ?: return
        viewModelScope.launch {
            repository.addTrackToPlaylist(playlistId, track.id)
            _state.update { it.copy(addToPlaylistTrack = null) }
        }
    }

    fun createPlaylistAndAddTrack(name: String) {
        val track = _state.value.addToPlaylistTrack ?: return
        viewModelScope.launch {
            val id = repository.createPlaylist(name)
            repository.addTrackToPlaylist(id, track.id)
            _state.update { it.copy(addToPlaylistTrack = null) }
        }
    }
}
