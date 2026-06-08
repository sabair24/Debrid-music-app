package com.debridmusic.app.player

import androidx.media3.session.MediaController
import com.debridmusic.app.data.local.SettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class CrossFadeManager @Inject constructor(
    private val settingsStore: SettingsStore,
) {
    var crossFadeDurationMs: Long = 0L
        private set

    private var fadeInJob: Job? = null
    private var wasFadingOut = false

    fun init(scope: CoroutineScope) {
        scope.launch {
            settingsStore.crossFadeDurationMs.collect {
                crossFadeDurationMs = it.toLong()
            }
        }
    }

    fun checkFadeOut(controller: MediaController?, positionMs: Long, durationMs: Long) {
        if (crossFadeDurationMs <= 0 || controller == null || durationMs <= 0) return
        val remaining = durationMs - positionMs
        if (remaining in 1..<crossFadeDurationMs) {
            val fadeProgress = 1f - remaining.toFloat() / crossFadeDurationMs
            controller.volume = (1f - fadeProgress).coerceIn(0f, 1f)
            wasFadingOut = true
        }
    }

    fun onTrackTransition(controller: MediaController?, scope: CoroutineScope) {
        if (crossFadeDurationMs <= 0 || controller == null || !wasFadingOut) {
            controller?.volume = 1f
            return
        }
        wasFadingOut = false
        fadeInJob?.cancel()
        fadeInJob = scope.launch {
            controller.volume = 0f
            val steps = 20
            val stepMs = crossFadeDurationMs / steps
            for (step in 1..steps) {
                controller.volume = step.toFloat() / steps
                delay(stepMs)
            }
            controller.volume = 1f
        }
    }
}
