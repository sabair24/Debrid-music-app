package com.debridmusic.app.ui.playlist

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.repository.MusicRepository
import com.debridmusic.app.domain.model.Playlist
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

data class PlaylistsUiState(
    val playlists: List<Playlist> = emptyList(),
    val showCreateDialog: Boolean = false,
    val newPlaylistName: String = "",
)

@HiltViewModel
class PlaylistsViewModel @Inject constructor(
    private val repository: MusicRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(PlaylistsUiState())
    val state: StateFlow<PlaylistsUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            repository.observePlaylists().collect { playlists ->
                _state.update { it.copy(playlists = playlists) }
            }
        }
    }

    fun showCreateDialog() = _state.update { it.copy(showCreateDialog = true, newPlaylistName = "") }
    fun hideCreateDialog() = _state.update { it.copy(showCreateDialog = false) }
    fun setNewName(name: String) = _state.update { it.copy(newPlaylistName = name) }

    fun createPlaylist() {
        val name = _state.value.newPlaylistName.trim()
        if (name.isBlank()) return
        viewModelScope.launch {
            repository.createPlaylist(name)
            _state.update { it.copy(showCreateDialog = false, newPlaylistName = "") }
        }
    }

    fun deletePlaylist(id: Long) {
        viewModelScope.launch { repository.deletePlaylist(id) }
    }
}
