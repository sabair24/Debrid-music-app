package com.debridmusic.app.ui.downloads

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.local.entity.DownloadStatus
import com.debridmusic.app.domain.model.Download
import com.debridmusic.app.download.OfflineDownloadManager
import com.debridmusic.app.player.PlayerController
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

data class DownloadsUiState(
    val downloads: List<Download> = emptyList(),
)

@HiltViewModel
class DownloadsViewModel @Inject constructor(
    private val downloadManager: OfflineDownloadManager,
    val playerController: PlayerController,
) : ViewModel() {

    private val _state = MutableStateFlow(DownloadsUiState())
    val state: StateFlow<DownloadsUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            downloadManager.observeAll().collect { entities ->
                _state.update { s ->
                    s.copy(downloads = entities.mapNotNull { entity ->
                        runCatching {
                            Download(
                                id = entity.id,
                                title = entity.title,
                                artist = entity.artist,
                                album = entity.album,
                                sourceUrl = entity.sourceUrl,
                                localPath = entity.localPath,
                                sizeBytes = entity.sizeBytes,
                                downloadedBytes = entity.downloadedBytes,
                                status = DownloadStatus.valueOf(entity.status),
                                dateAdded = entity.dateAdded,
                                artworkUri = entity.artworkUri,
                            )
                        }.getOrNull()
                    })
                }
            }
        }
    }

    fun playDownload(download: Download) {
        if (!download.isComplete) return
        val uri = download.localPath.let {
            if (it.startsWith("content://") || it.startsWith("file://")) it else "file://$it"
        }
        playerController.playRemoteUrl(
            url = uri,
            title = download.title,
            artist = download.artist,
            album = download.album,
            artworkUri = download.artworkUri,
        )
    }

    fun deleteDownload(id: Long) {
        viewModelScope.launch { downloadManager.deleteDownload(id) }
    }
}
