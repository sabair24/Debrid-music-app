package com.debridmusic.app.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.remote.dto.TorBoxUser
import com.debridmusic.app.metadata.EnrichmentProgress
import com.debridmusic.app.metadata.MetadataEnricher
import com.debridmusic.app.player.EqController
import com.debridmusic.app.player.ScrobbleManager
import com.debridmusic.app.torbox.TorBoxAuthInterceptor
import com.debridmusic.app.torbox.TorBoxRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SettingsUiState(
    val lastFmApiKey: String = "",
    val discogsToken: String = "",
    val torBoxApiKey: String = "",
    val isEnriching: Boolean = false,
    val enrichProgress: EnrichmentProgress? = null,
    val enrichResult: String? = null,
    val torBoxUser: TorBoxUser? = null,
    val torBoxValidating: Boolean = false,
    val torBoxError: String? = null,
    // EQ
    val eqEnabled: Boolean = false,
    val eqBands: List<Float> = List(5) { 0f },
    val eqRangeDb: ClosedFloatingPointRange<Float> = -12f..12f,
    // Cross-fade
    val crossFadeDurationMs: Int = 0,
    // Last.fm scrobble
    val lastFmUsername: String = "",
    val lastFmSessionKey: String = "",
    val lastFmApiSecret: String = "",
    val lastFmPassword: String = "",
    val lastFmLoginLoading: Boolean = false,
    val lastFmLoginError: String? = null,
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settingsStore: SettingsStore,
    private val metadataEnricher: MetadataEnricher,
    private val torBoxRepository: TorBoxRepository,
    private val torBoxAuthInterceptor: TorBoxAuthInterceptor,
    val eqController: EqController,
    private val scrobbleManager: ScrobbleManager,
) : ViewModel() {

    private val _state = MutableStateFlow(SettingsUiState())
    val state: StateFlow<SettingsUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            combine(
                settingsStore.lastFmApiKey,
                settingsStore.discogsToken,
                settingsStore.torBoxApiKey,
                settingsStore.eqEnabled,
                settingsStore.eqBandGains,
            ) { lfm, discogs, torbox, eqOn, eqBands -> listOf(lfm, discogs, torbox, eqOn.toString(), eqBands) }
                .collect { (lfm, discogs, torbox, eqOn, eqBands) ->
                    val gains = eqBands.split(",").mapNotNull { it.toFloatOrNull() }
                    _state.update {
                        it.copy(
                            lastFmApiKey = lfm,
                            discogsToken = discogs,
                            torBoxApiKey = torbox,
                            eqEnabled = eqOn.toBoolean(),
                            eqBands = gains.ifEmpty { List(5) { 0f } },
                        )
                    }
                    torBoxAuthInterceptor.apiKey = torbox
                }
        }
        viewModelScope.launch {
            settingsStore.crossFadeDurationMs.collect { ms ->
                _state.update { it.copy(crossFadeDurationMs = ms) }
            }
        }
        viewModelScope.launch {
            combine(
                settingsStore.lastFmUsername,
                settingsStore.lastFmSessionKey,
            ) { u, sk -> Pair(u, sk) }.collect { (u, sk) ->
                _state.update { it.copy(lastFmUsername = u, lastFmSessionKey = sk) }
            }
        }
        viewModelScope.launch {
            eqController.isEnabled.collect { enabled ->
                _state.update { it.copy(eqEnabled = enabled) }
            }
        }
        viewModelScope.launch {
            eqController.bands.collect { bands ->
                _state.update { it.copy(eqBands = bands, eqRangeDb = eqController.bandRangeDb) }
            }
        }
    }

    fun setLastFmApiKey(key: String) = _state.update { it.copy(lastFmApiKey = key) }
    fun setDiscogsToken(token: String) = _state.update { it.copy(discogsToken = token) }
    fun setTorBoxApiKey(key: String) = _state.update { it.copy(torBoxApiKey = key, torBoxUser = null, torBoxError = null) }

    fun saveKeys() {
        viewModelScope.launch {
            settingsStore.setLastFmApiKey(_state.value.lastFmApiKey)
            settingsStore.setDiscogsToken(_state.value.discogsToken)
            settingsStore.setTorBoxApiKey(_state.value.torBoxApiKey)
            torBoxAuthInterceptor.apiKey = _state.value.torBoxApiKey
        }
    }

    fun validateTorBoxKey() {
        _state.update { it.copy(torBoxValidating = true, torBoxUser = null, torBoxError = null) }
        viewModelScope.launch {
            // Save to DataStore first so syncApiKey() inside the repository reads the correct value
            settingsStore.setTorBoxApiKey(_state.value.torBoxApiKey)
            torBoxAuthInterceptor.apiKey = _state.value.torBoxApiKey
            torBoxRepository.validateApiKey()
                .onSuccess { user ->
                    _state.update { it.copy(torBoxValidating = false, torBoxUser = user) }
                }
                .onFailure { e ->
                    _state.update { it.copy(torBoxValidating = false, torBoxError = e.message) }
                }
        }
    }

    fun enrichLibrary() {
        if (_state.value.isEnriching) return
        _state.update { it.copy(isEnriching = true, enrichResult = null) }
        viewModelScope.launch {
            val count = metadataEnricher.enrichAll { progress ->
                _state.update { it.copy(enrichProgress = progress) }
            }
            _state.update {
                it.copy(isEnriching = false, enrichProgress = null, enrichResult = "Enriched $count items")
            }
        }
    }

    // ── EQ ───────────────────────────────────────────────────────────────────
    fun setEqEnabled(enabled: Boolean) = eqController.setEnabled(enabled, viewModelScope)

    fun setEqBandGain(index: Int, gainDb: Float) =
        eqController.setBandGain(index, gainDb, viewModelScope)

    // ── Cross-fade ────────────────────────────────────────────────────────────
    fun setCrossFadeDuration(ms: Int) {
        _state.update { it.copy(crossFadeDurationMs = ms) }
        viewModelScope.launch { settingsStore.setCrossFadeDurationMs(ms) }
    }

    // ── Last.fm scrobble ──────────────────────────────────────────────────────
    fun setLastFmPassword(pw: String) = _state.update { it.copy(lastFmPassword = pw) }
    fun setLastFmApiSecret(secret: String) = _state.update { it.copy(lastFmApiSecret = secret) }

    fun loginLastFm() {
        val s = _state.value
        if (s.lastFmUsername.isBlank() || s.lastFmPassword.isBlank() ||
            s.lastFmApiKey.isBlank() || s.lastFmApiSecret.isBlank()) return
        _state.update { it.copy(lastFmLoginLoading = true, lastFmLoginError = null) }
        viewModelScope.launch {
            scrobbleManager.login(
                username = s.lastFmUsername,
                password = s.lastFmPassword,
                apiKey = s.lastFmApiKey,
                apiSecret = s.lastFmApiSecret,
            ).onSuccess {
                _state.update { it.copy(lastFmLoginLoading = false, lastFmPassword = "") }
            }.onFailure { e ->
                _state.update { it.copy(lastFmLoginLoading = false, lastFmLoginError = e.message) }
            }
        }
    }

    fun setLastFmUsernameInput(u: String) = _state.update { it.copy(lastFmUsername = u) }

    fun logoutLastFm() {
        viewModelScope.launch {
            settingsStore.clearLastFmSession()
            _state.update { it.copy(lastFmSessionKey = "", lastFmUsername = "") }
        }
    }
}
