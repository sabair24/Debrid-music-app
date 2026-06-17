package com.debridmusic.app.ui.player

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.player.PlayerController
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class PlayerViewModel @Inject constructor(
    val playerController: PlayerController,
) : ViewModel() {

    val isPlaying = playerController.isPlaying
    val currentTrack = playerController.currentTrack
    val positionMs = playerController.positionMs
    val durationMs = playerController.durationMs
    val shuffleEnabled = playerController.shuffleEnabled
    val repeatMode = playerController.repeatMode

    init {
        viewModelScope.launch {
            while (true) {
                delay(500)
                playerController.updatePosition()
            }
        }
    }

    fun togglePlayPause() = playerController.togglePlayPause()
    fun skipToNext() = playerController.skipToNext()
    fun skipToPrevious() = playerController.skipToPrevious()
    fun seekTo(positionMs: Long) = playerController.seekTo(positionMs)
    fun toggleShuffle() = playerController.toggleShuffle()
    fun cycleRepeat() = playerController.cycleRepeat()
}
