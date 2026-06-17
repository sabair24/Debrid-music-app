package com.debridmusic.app.player

import android.content.ComponentName
import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.domain.model.RepeatMode
import com.debridmusic.app.domain.model.Track
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PlayerController @Inject constructor(
    @ApplicationContext private val context: Context,
    private val crossFadeManager: CrossFadeManager,
    private val scrobbleManager: ScrobbleManager,
    private val settingsStore: SettingsStore,
) {
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var controller: MediaController? = null

    private val controllerScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _currentTrack = MutableStateFlow<Track?>(null)
    val currentTrack: StateFlow<Track?> = _currentTrack.asStateFlow()

    private val _positionMs = MutableStateFlow(0L)
    val positionMs: StateFlow<Long> = _positionMs.asStateFlow()

    private val _durationMs = MutableStateFlow(0L)
    val durationMs: StateFlow<Long> = _durationMs.asStateFlow()

    private val _shuffleEnabled = MutableStateFlow(false)
    val shuffleEnabled: StateFlow<Boolean> = _shuffleEnabled.asStateFlow()

    private val _repeatMode = MutableStateFlow(RepeatMode.OFF)
    val repeatMode: StateFlow<RepeatMode> = _repeatMode.asStateFlow()

    private var currentQueue: List<Track> = emptyList()

    fun connect() {
        if (controllerFuture != null) return // idempotent — safe to call from multiple entry points
        crossFadeManager.init(controllerScope)
        scrobbleManager.init(this, controllerScope)

        val sessionToken = SessionToken(
            context,
            ComponentName(context, MusicPlayerService::class.java)
        )
        controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        controllerFuture?.addListener({
            controller = controllerFuture?.get()
            controller?.addListener(playerListener)
            // Restore persisted shuffle/repeat onto the freshly-connected controller.
            controllerScope.launch {
                val shuffle = settingsStore.shuffleEnabled.first()
                val repeat = RepeatMode.entries.getOrElse(settingsStore.repeatMode.first()) { RepeatMode.OFF }
                controller?.shuffleModeEnabled = shuffle
                controller?.repeatMode = repeat.toMedia3()
                _shuffleEnabled.value = shuffle
                _repeatMode.value = repeat
            }
        }, MoreExecutors.directExecutor())
    }

    // ── Shuffle / repeat ────────────────────────────────────────────────────────
    fun toggleShuffle() = setShuffle(!_shuffleEnabled.value)

    fun setShuffle(enabled: Boolean) {
        controller?.shuffleModeEnabled = enabled
        _shuffleEnabled.value = enabled
        controllerScope.launch { settingsStore.setShuffleEnabled(enabled) }
    }

    fun cycleRepeat() {
        val next = when (_repeatMode.value) {
            RepeatMode.OFF -> RepeatMode.ALL
            RepeatMode.ALL -> RepeatMode.ONE
            RepeatMode.ONE -> RepeatMode.OFF
        }
        setRepeat(next)
    }

    fun setRepeat(mode: RepeatMode) {
        controller?.repeatMode = mode.toMedia3()
        _repeatMode.value = mode
        controllerScope.launch { settingsStore.setRepeatMode(mode.ordinal) }
    }

    private fun RepeatMode.toMedia3(): Int = when (this) {
        RepeatMode.OFF -> Player.REPEAT_MODE_OFF
        RepeatMode.ONE -> Player.REPEAT_MODE_ONE
        RepeatMode.ALL -> Player.REPEAT_MODE_ALL
    }

    private fun Int.toRepeatMode(): RepeatMode = when (this) {
        Player.REPEAT_MODE_ONE -> RepeatMode.ONE
        Player.REPEAT_MODE_ALL -> RepeatMode.ALL
        else -> RepeatMode.OFF
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

    fun playRemoteUrl(url: String, title: String, artist: String, album: String, artworkUri: String? = null) {
        val metadata = MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(artist)
            .setAlbumTitle(album)
            .setArtworkUri(artworkUri?.let { android.net.Uri.parse(it) })
            .build()
        val item = MediaItem.Builder()
            .setUri(url)
            .setMediaId("remote:$url")
            .setMediaMetadata(metadata)
            .build()
        val syntheticTrack = Track(
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
            artworkUri = artworkUri,
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
        controller?.let { ctrl ->
            val pos = ctrl.currentPosition
            val dur = ctrl.duration.coerceAtLeast(0L)
            _positionMs.value = pos
            _durationMs.value = dur
            crossFadeManager.checkFadeOut(ctrl, pos, dur)
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
            crossFadeManager.onTrackTransition(controller, controllerScope)
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            controller?.let {
                _isPlaying.value = it.isPlaying
                _durationMs.value = it.duration.coerceAtLeast(0L)
            }
        }

        override fun onShuffleModeEnabledChanged(shuffleModeEnabled: Boolean) {
            _shuffleEnabled.value = shuffleModeEnabled
        }

        override fun onRepeatModeChanged(repeatMode: Int) {
            _repeatMode.value = repeatMode.toRepeatMode()
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
