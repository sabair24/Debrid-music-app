package com.debridmusic.app.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.remote.dto.TorBoxUser
import com.debridmusic.app.metadata.EnrichmentProgress
import com.debridmusic.app.metadata.MetadataEnricher
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
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settingsStore: SettingsStore,
    private val metadataEnricher: MetadataEnricher,
    private val torBoxRepository: TorBoxRepository,
    private val torBoxAuthInterceptor: TorBoxAuthInterceptor,
) : ViewModel() {

    private val _state = MutableStateFlow(SettingsUiState())
    val state: StateFlow<SettingsUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            combine(
                settingsStore.lastFmApiKey,
                settingsStore.discogsToken,
                settingsStore.torBoxApiKey,
            ) { lfm, discogs, torbox -> Triple(lfm, discogs, torbox) }
                .collect { (lfm, discogs, torbox) ->
                    _state.update { it.copy(lastFmApiKey = lfm, discogsToken = discogs, torBoxApiKey = torbox) }
                    torBoxAuthInterceptor.apiKey = torbox
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
                it.copy(
                    isEnriching = false,
                    enrichProgress = null,
                    enrichResult = "Enriched $count items",
                )
            }
        }
    }
}
