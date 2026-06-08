package com.debridmusic.app.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.metadata.EnrichmentProgress
import com.debridmusic.app.metadata.MetadataEnricher
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SettingsUiState(
    val lastFmApiKey: String = "",
    val discogsToken: String = "",
    val isEnriching: Boolean = false,
    val enrichProgress: EnrichmentProgress? = null,
    val enrichResult: String? = null,
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settingsStore: SettingsStore,
    private val metadataEnricher: MetadataEnricher,
) : ViewModel() {

    private val _state = MutableStateFlow(SettingsUiState())
    val state: StateFlow<SettingsUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            combine(settingsStore.lastFmApiKey, settingsStore.discogsToken) { lfm, discogs ->
                lfm to discogs
            }.collect { (lfm, discogs) ->
                _state.update { it.copy(lastFmApiKey = lfm, discogsToken = discogs) }
            }
        }
    }

    fun setLastFmApiKey(key: String) = _state.update { it.copy(lastFmApiKey = key) }
    fun setDiscogsToken(token: String) = _state.update { it.copy(discogsToken = token) }

    fun saveKeys() {
        viewModelScope.launch {
            settingsStore.setLastFmApiKey(_state.value.lastFmApiKey)
            settingsStore.setDiscogsToken(_state.value.discogsToken)
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
