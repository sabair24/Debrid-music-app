package com.debridmusic.app.ui.soulseek

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.metadata.StreamArtworkResolver
import com.debridmusic.app.player.PlayerController
import com.debridmusic.app.soulseek.SlskDownloadState
import com.debridmusic.app.soulseek.SoulseekFile
import com.debridmusic.app.soulseek.SoulseekPath
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
    val downloadStatus: String? = null,
    val downloadError: String? = null,
    val downloadInfo: String? = null,
)

@HiltViewModel
class SoulseekSearchViewModel @Inject constructor(
    private val repository: SoulseekRepository,
    val playerController: PlayerController,
    private val artworkResolver: StreamArtworkResolver,
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
        _state.update { it.copy(
            downloadingFile = file, downloadProgress = 0f,
            downloadStatus = "Verbinden…", downloadError = null, downloadInfo = null,
        ) }

        downloadJob = viewModelScope.launch {
            repository.download(file).collect { dlState ->
                when (dlState) {
                    is SlskDownloadState.Downloading -> {
                        val progress = if (dlState.totalBytes > 0)
                            dlState.bytesReceived.toFloat() / dlState.totalBytes else 0f
                        _state.update { it.copy(
                            downloadProgress = progress,
                            downloadStatus = if (dlState.totalBytes > 0) "Downloaden…"
                                             else "Aangevraagd — wachten op upload-slot…",
                        ) }
                    }
                    is SlskDownloadState.Done -> {
                        _state.update { it.copy(downloadingFile = null, downloadProgress = 0f, downloadStatus = null) }
                        // localPath is already a playable URI: content:// (MediaStore,
                        // Android 10+) or file://… on older versions.
                        val uri = dlState.localPath.let {
                            if (it.startsWith("content://") || it.startsWith("file://")) it else "file://$it"
                        }
                        val meta = SoulseekPath.parse(file.filename)
                        playerController.playRemoteUrl(
                            url = uri,
                            title = meta.title.ifBlank { file.displayName },
                            artist = meta.artist.ifBlank { file.username },
                            album = meta.album,
                            artworkUri = artworkResolver.resolve(meta.artist, meta.title, meta.album),
                        )
                    }
                    // Queued is informational (the uploader put us in their queue) — not a
                    // hard error, and we keep the results list visible.
                    is SlskDownloadState.Queued -> {
                        _state.update { it.copy(
                            downloadingFile = null, downloadProgress = 0f, downloadStatus = null,
                            downloadInfo = dlState.reason,
                        ) }
                    }
                    is SlskDownloadState.Error -> {
                        _state.update { it.copy(
                            downloadingFile = null, downloadProgress = 0f, downloadStatus = null,
                            downloadInfo = dlState.message,
                        ) }
                    }
                }
            }
        }
    }

    fun cancelDownload() {
        downloadJob?.cancel()
        _state.update { it.copy(downloadingFile = null, downloadProgress = 0f, downloadStatus = null) }
    }

    fun clearDownloadInfo() = _state.update { it.copy(downloadInfo = null) }
}
