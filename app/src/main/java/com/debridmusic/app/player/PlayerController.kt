package com.debridmusic.app.player

import android.content.ComponentName
import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.debridmusic.app.domain.model.Track
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PlayerController @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var controller: MediaController? = null

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _currentTrack = MutableStateFlow<Track?>(null)
    val currentTrack: StateFlow<Track?> = _currentTrack.asStateFlow()

    private val _positionMs = MutableStateFlow(0L)
    val positionMs: StateFlow<Long> = _positionMs.asStateFlow()

    private val _durationMs = MutableStateFlow(0L)
    val durationMs: StateFlow<Long> = _durationMs.asStateFlow()

    private var currentQueue: List<Track> = emptyList()

    fun connect() {
        val sessionToken = SessionToken(
            context,
            ComponentName(context, MusicPlayerService::class.java)
        )
        controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        controllerFuture?.addListener({
            controller = controllerFuture?.get()
            controller?.addListener(playerListener)
        }, MoreExecutors.directExecutor())
    }

    fun disconnect() {
        controller?.removeListener(playerListener)
        controllerFuture?.let { MediaController.releaseFuture(it) }
        controller = null
    }

    fun playQueue(tracks: List<Track>, startIndex: Int = 0) {
        currentQueue = tracks
        val items = tracks.map { it.toMediaItem() }
        controller?.run {
            setMediaItems(items, startIndex, 0L)
            prepare()
            play()
        }
    }

    fun playTrack(track: Track) {
        currentQueue = listOf(track)
        controller?.run {
            setMediaItem(track.toMediaItem())
            prepare()
            play()
        }
    }

    fun togglePlayPause() {
        controller?.let { if (it.isPlaying) it.pause() else it.play() }
    }

    fun seekTo(positionMs: Long) { controller?.seekTo(positionMs) }

    fun skipToNext() { controller?.seekToNextMediaItem() }

    fun skipToPrevious() { controller?.seekToPreviousMediaItem() }

    fun playRemoteUrl(url: String, title: String, artist: String, album: String) {
        val metadata = MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(artist)
            .setAlbumTitle(album)
            .build()
        val item = MediaItem.Builder()
            .setUri(url)
            .setMediaId("remote:$url")
            .setMediaMetadata(metadata)
            .build()
        // Represent as a synthetic Track so currentTrack flow updates
        val syntheticTrack = com.debridmusic.app.domain.model.Track(
            id = -1L,
            title = title,
            artistName = artist,
            albumTitle = album,
            albumId = -1L,
            artistId = -1L,
            uri = url,
            durationMs = 0L,
            trackNumber = 0,
            discNumber = 1,
            year = null,
            artworkUri = null,
            genre = null,
            bitrate = null,
            sampleRate = null,
            isLossless = url.contains("flac", ignoreCase = true),
            fileSize = 0L,
            dateAdded = System.currentTimeMillis(),
        )
        currentQueue = listOf(syntheticTrack)
        _currentTrack.value = syntheticTrack
        controller?.run {
            setMediaItem(item)
            prepare()
            play()
        }
    }

    fun updatePosition() {
        controller?.let {
            _positionMs.value = it.currentPosition
            _durationMs.value = it.duration.coerceAtLeast(0L)
        }
    }

    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            _isPlaying.value = isPlaying
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            val index = controller?.currentMediaItemIndex ?: return
            _currentTrack.value = currentQueue.getOrNull(index)
            _durationMs.value = controller?.duration?.coerceAtLeast(0L) ?: 0L
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            controller?.let {
                _isPlaying.value = it.isPlaying
                _durationMs.value = it.duration.coerceAtLeast(0L)
            }
        }
    }

    private fun Track.toMediaItem(): MediaItem {
        val metadata = MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(artistName)
            .setAlbumTitle(albumTitle)
            .setTrackNumber(trackNumber)
            .setArtworkUri(artworkUri?.let { android.net.Uri.parse(it) })
            .build()
        return MediaItem.Builder()
            .setUri(uri)
            .setMediaId(id.toString())
            .setMediaMetadata(metadata)
            .build()
    }
}
