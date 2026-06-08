package com.debridmusic.app.ui.soulseek

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.player.PlayerController
import com.debridmusic.app.soulseek.SlskDownloadState
import com.debridmusic.app.soulseek.SoulseekFile
import com.debridmusic.app.soulseek.SoulseekRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SoulseekUiState(
    val query: String = "",
    val isSearching: Boolean = false,
    val searchError: String? = null,
    val results: List<SoulseekFile> = emptyList(),
    val downloadingFile: SoulseekFile? = null,
    val downloadProgress: Float = 0f,
    val downloadError: String? = null,
)

@HiltViewModel
class SoulseekSearchViewModel @Inject constructor(
    private val repository: SoulseekRepository,
    val playerController: PlayerController,
) : ViewModel() {

    private val _state = MutableStateFlow(SoulseekUiState())
    val state: StateFlow<SoulseekUiState> = _state.asStateFlow()

    private var downloadJob: Job? = null

    fun setQuery(q: String) = _state.update { it.copy(query = q, searchError = null) }

    fun search() {
        val query = _state.value.query.trim()
        if (query.isBlank()) return
        _state.update { it.copy(isSearching = true, results = emptyList(), searchError = null) }
        viewModelScope.launch {
            repository.search(query)
                .onSuccess { files -> _state.update { it.copy(isSearching = false, results = files) } }
                .onFailure { e -> _state.update { it.copy(isSearching = false, searchError = e.message) } }
        }
    }

    fun downloadAndPlay(file: SoulseekFile) {
        if (_state.value.downloadingFile != null) return
        downloadJob?.cancel()
        _state.update { it.copy(downloadingFile = file, downloadProgress = 0f, downloadError = null) }

        downloadJob = viewModelScope.launch {
            repository.download(file).collect { dlState ->
                when (dlState) {
                    is SlskDownloadState.Downloading -> {
                        val progress = if (dlState.totalBytes > 0)
                            dlState.bytesReceived.toFloat() / dlState.totalBytes else 0f
                        _state.update { it.copy(downloadProgress = progress) }
                    }
                    is SlskDownloadState.Done -> {
                        _state.update { it.copy(downloadingFile = null, downloadProgress = 0f) }
                        playerController.playRemoteUrl(
                            url = "file://${dlState.localPath}",
                            title = file.displayName,
                            artist = file.username,
                            album = "",
                        )
                    }
                    is SlskDownloadState.Queued -> {
                        _state.update { it.copy(
                            downloadingFile = null,
                            downloadError = "Gequeued: ${dlState.reason} — probeer een ander bestand",
                        ) }
                    }
                    is SlskDownloadState.Error -> {
                        _state.update { it.copy(downloadingFile = null, downloadError = dlState.message) }
                    }
                }
            }
        }
    }

    fun cancelDownload() {
        downloadJob?.cancel()
        _state.update { it.copy(downloadingFile = null, downloadProgress = 0f) }
    }
}
