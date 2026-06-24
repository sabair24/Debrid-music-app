package com.debridmusic.app.ui.catalogue

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.remote.dto.TorBoxFile
import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.data.remote.dto.TorBoxTorrentItem
import com.debridmusic.app.data.repository.BrowseRepository
import com.debridmusic.app.domain.model.BrowseArtist
import com.debridmusic.app.domain.model.Track
import com.debridmusic.app.download.DownloadRequest
import com.debridmusic.app.download.OfflineDownloadManager
import com.debridmusic.app.metadata.StreamArtworkResolver
import com.debridmusic.app.player.PlayerController
import com.debridmusic.app.torbox.StreamState
import com.debridmusic.app.torbox.TorBoxRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

data class CatalogueSearchUiState(
    val query: String = "",
    val results: List<TorBoxSearchResult> = emptyList(),
    val artists: List<BrowseArtist> = emptyList(),
    val isSearching: Boolean = false,
    val searchError: String? = null,
    val streamingId: String? = null,
    val streamState: StreamState = StreamState.Idle,
    val downloadingHash: String? = null,
    val downloadInfo: String? = null,
)

@HiltViewModel
class CatalogueSearchViewModel @Inject constructor(
    private val torBoxRepository: TorBoxRepository,
    val playerController: PlayerController,
    private val offlineDownloadManager: OfflineDownloadManager,
    private val artworkResolver: StreamArtworkResolver,
    private val browseRepository: BrowseRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(CatalogueSearchUiState())
    val state: StateFlow<CatalogueSearchUiState> = _state.asStateFlow()

    private var streamJob: Job? = null

    fun setQuery(q: String) = _state.update { it.copy(query = q, searchError = null) }

    fun search() {
        val query = _state.value.query.trim()
        if (query.isBlank()) return
        _state.update { it.copy(isSearching = true, results = emptyList(), artists = emptyList(), searchError = null) }
        // Artist matches (Deezer) load in parallel and feed the "Stremio" browse.
        viewModelScope.launch {
            val artists = browseRepository.searchArtists(query)
            _state.update { it.copy(artists = artists) }
        }
        viewModelScope.launch {
            torBoxRepository.search(query)
                .onSuccess { results ->
                    _state.update { it.copy(isSearching = false, results = results) }
                }
                .onFailure { e ->
                    _state.update { it.copy(isSearching = false, searchError = e.message) }
                }
        }
    }

    fun stream(result: TorBoxSearchResult, albumMode: Boolean = false) {
        if (_state.value.streamingId == result.hash) return
        streamJob?.cancel()
        _state.update { it.copy(streamingId = result.hash, streamState = StreamState.Idle) }

        streamJob = viewModelScope.launch {
            // Try the tapped result first, then fall back to other cached (instant)
            // results if it stalls/fails — so a dead torrent doesn't sink the tap.
            val candidates = buildList {
                add(result)
                addAll(_state.value.results.filter { it.hash != result.hash && it.cached }.take(MAX_FALLBACKS))
            }
            var lastError: StreamState.Error? = null
            for ((index, candidate) in candidates.withIndex()) {
                if (index > 0) _state.update { it.copy(streamState = StreamState.Queuing(candidate.name)) }
                var terminalError: StreamState.Error? = null
                var played = false
                val flow = if (albumMode) torBoxRepository.streamAlbum(candidate)
                else torBoxRepository.streamResult(candidate)
                flow.collect { state ->
                    when (state) {
                        is StreamState.Ready -> { _state.update { it.copy(streamState = state) }; playStreamUrl(state); played = true }
                        is StreamState.ReadyAlbum -> { _state.update { it.copy(streamState = state) }; playAlbumQueue(state); played = true }
                        is StreamState.Error -> terminalError = state
                        else -> _state.update { it.copy(streamState = state) }
                    }
                }
                if (played) return@launch
                lastError = terminalError
            }
            _state.update { it.copy(streamState = lastError ?: StreamState.Error("Geen werkende bron gevonden")) }
        }
    }

    fun streamTrackPicker(result: TorBoxSearchResult) {
        if (_state.value.streamingId == result.hash) return
        streamJob?.cancel()
        _state.update { it.copy(streamingId = result.hash, streamState = StreamState.Idle) }

        streamJob = viewModelScope.launch {
            torBoxRepository.streamTrackPicker(result).collect { state ->
                _state.update { it.copy(streamState = state) }
            }
        }
    }

    fun playSelectedTrack(torrentItem: com.debridmusic.app.data.remote.dto.TorBoxTorrentItem, file: TorBoxFile) {
        viewModelScope.launch {
            val result = runCatching { torBoxRepository.resolveTrackUrl(torrentItem, file) }
            result.onSuccess { url ->
                val ready = StreamState.Ready(url, torrentItem, file)
                _state.update { it.copy(streamState = ready) }
                playStreamUrl(ready)
            }.onFailure { e ->
                _state.update { it.copy(streamState = StreamState.Error(e.message ?: "Failed to resolve URL")) }
            }
        }
    }

    fun cancelStream() {
        streamJob?.cancel()
        _state.update { it.copy(streamingId = null, streamState = StreamState.Idle) }
    }

    private suspend fun playStreamUrl(ready: StreamState.Ready) {
        val title = ready.file.shortName ?: ready.file.name
        val artist = extractArtistFromName(ready.torrentItem.name)
        val album = ready.torrentItem.name
        playerController.playRemoteUrl(
            url = ready.streamUrl,
            title = title,
            artist = artist,
            album = album,
            artworkUri = artworkResolver.resolve(artist, title, album),
        )
    }

    private suspend fun playAlbumQueue(ready: StreamState.ReadyAlbum) {
        val albumName = ready.torrentItem.name
        val artist = extractArtistFromName(albumName)
        val art = artworkResolver.resolve(artist, albumName, albumName)
        val tracks = ready.tracks.mapIndexed { index, albumTrack ->
            Track(
                id = -(index + 1L),
                title = albumTrack.file.shortName ?: albumTrack.file.name,
                artistName = artist,
                albumTitle = albumName,
                albumId = -1L,
                artistId = -1L,
                uri = albumTrack.url,
                durationMs = 0L,
                trackNumber = index + 1,
                discNumber = 1,
                year = null,
                artworkUri = art,
                genre = null,
                bitrate = null,
                sampleRate = null,
                isLossless = albumTrack.file.isFlac,
                fileSize = albumTrack.file.size,
                dateAdded = System.currentTimeMillis(),
            )
        }
        playerController.playQueue(tracks)
    }

    /** Queue the currently-streaming track for offline download (sequential queue). */
    fun downloadCurrentStream() {
        val ready = _state.value.streamState as? StreamState.Ready ?: return
        viewModelScope.launch {
            val title = ready.file.shortName ?: ready.file.name
            val artist = extractArtistFromName(ready.torrentItem.name)
            val album = ready.torrentItem.name
            offlineDownloadManager.enqueue(
                DownloadRequest(title, artist, album, ready.streamUrl, artworkResolver.resolve(artist, title, album))
            )
            _state.update { it.copy(downloadInfo = "\"$title\" toegevoegd aan downloads") }
        }
    }

    /** Queue a single track picked from the track-picker sheet. */
    fun downloadPickedTrack(torrentItem: TorBoxTorrentItem, file: TorBoxFile) {
        viewModelScope.launch {
            val url = runCatching { torBoxRepository.resolveTrackUrl(torrentItem, file) }.getOrNull() ?: return@launch
            val title = file.shortName ?: file.name
            val artist = extractArtistFromName(torrentItem.name)
            offlineDownloadManager.enqueue(
                DownloadRequest(title, artist, torrentItem.name, url, artworkResolver.resolve(artist, title, torrentItem.name))
            )
            _state.update { it.copy(downloadInfo = "\"$title\" toegevoegd aan downloads") }
        }
    }

    /** Queue every audio track of a torrent — full-album download (sequential). */
    fun downloadAllTracks(torrentItem: TorBoxTorrentItem, files: List<TorBoxFile>) {
        viewModelScope.launch {
            val artist = extractArtistFromName(torrentItem.name)
            val art = artworkResolver.resolve(artist, torrentItem.name, torrentItem.name)
            val requests = files.mapNotNull { file ->
                val url = runCatching { torBoxRepository.resolveTrackUrl(torrentItem, file) }.getOrNull() ?: return@mapNotNull null
                DownloadRequest(file.shortName ?: file.name, artist, torrentItem.name, url, art)
            }
            offlineDownloadManager.enqueueAll(requests)
            _state.update { it.copy(downloadInfo = "${requests.size} tracks toegevoegd aan downloads") }
        }
    }

    fun clearDownloadInfo() = _state.update { it.copy(downloadInfo = null) }

    private fun extractArtistFromName(torrentName: String): String {
        val dash = torrentName.indexOf(" - ")
        return if (dash > 0) torrentName.substring(0, dash).trim() else torrentName
    }

    private companion object {
        const val MAX_FALLBACKS = 3   // cached alternatives to try if the tap stalls
    }
}
