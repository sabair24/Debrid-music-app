package com.debridmusic.app.player

import android.media.audiofx.Equalizer
import com.debridmusic.app.data.local.SettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class EqController @Inject constructor(
    private val settingsStore: SettingsStore,
) {
    private var equalizer: Equalizer? = null

    private val _isEnabled = MutableStateFlow(false)
    val isEnabled: StateFlow<Boolean> = _isEnabled.asStateFlow()

    private val _bands = MutableStateFlow(List(5) { 0f })
    val bands: StateFlow<List<Float>> = _bands.asStateFlow()

    // Center frequencies shown in UI (Hz)
    val bandLabels = listOf("60 Hz", "230 Hz", "910 Hz", "3.6 kHz", "14 kHz")

    // Range the hardware supports (millibels). Populated after attach.
    var bandRangeDb: ClosedFloatingPointRange<Float> = -12f..12f
        private set

    fun attachSession(audioSessionId: Int, scope: CoroutineScope) {
        equalizer?.release()
        try {
            equalizer = Equalizer(0, audioSessionId).apply {
                val range = bandLevelRange
                bandRangeDb = (range[0] / 100f)..(range[1] / 100f)
                // Load persisted settings
                scope.launch {
                    settingsStore.eqEnabled.collect { enabled ->
                        _isEnabled.value = enabled
                        this@apply.enabled = enabled
                    }
                }
                scope.launch {
                    settingsStore.eqBandGains.collect { csv ->
                        val gains = csv.split(",").mapNotNull { it.toFloatOrNull() }
                        val count = numberOfBands.toInt()
                        if (gains.size >= count) {
                            _bands.value = gains.take(count)
                            gains.take(count).forEachIndexed { i, gainDb ->
                                val mb = (gainDb * 100f).toInt().toShort()
                                    .coerceIn(range[0], range[1])
                                setBandLevel(i.toShort(), mb)
                            }
                        }
                    }
                }
            }
        } catch (_: Exception) {
            // Equalizer unavailable on this device
        }
    }

    fun setEnabled(enabled: Boolean, scope: CoroutineScope) {
        _isEnabled.value = enabled
        equalizer?.enabled = enabled
        scope.launch { settingsStore.setEqEnabled(enabled) }
    }

    fun setBandGain(index: Int, gainDb: Float, scope: CoroutineScope) {
        val current = _bands.value.toMutableList()
        if (index !in current.indices) return
        current[index] = gainDb
        _bands.value = current
        equalizer?.let { eq ->
            val mb = (gainDb * 100f).toInt().toShort()
                .coerceIn(eq.bandLevelRange[0], eq.bandLevelRange[1])
            eq.setBandLevel(index.toShort(), mb)
        }
        scope.launch { settingsStore.setEqBandGains(current.joinToString(",")) }
    }

    fun release() {
        equalizer?.release()
        equalizer = null
    }
}

private fun Short.coerceIn(min: Short, max: Short): Short =
    maxOf(min, minOf(max, this))
