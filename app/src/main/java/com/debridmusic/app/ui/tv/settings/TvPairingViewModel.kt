package com.debridmusic.app.ui.tv.settings

import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.repository.MusicRepository
import com.debridmusic.app.server.DiscoveredServer
import com.debridmusic.app.server.ServerDiscovery
import com.debridmusic.app.server.ServerRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class TvPairingUiState(
    val searching: Boolean = false,
    val servers: List<DiscoveredServer> = emptyList(),
    val selected: DiscoveredServer? = null,
    val code: String = "",
    val pairing: Boolean = false,
    val message: String = "",
    val pairedName: String = "",
    val trackCount: Int = 0,
    val connectedUrl: String = "",
)

/**
 * Pairing this TV with the PC.
 *
 * Six digits, not a token: the access token is 32 hex characters, and entering that on a TV
 * remote via an on-screen keyboard is a genuinely miserable few minutes. The PC shows a code,
 * this screen takes it, and the token comes back over the wire.
 */
@HiltViewModel
class TvPairingViewModel @Inject constructor(
    private val discovery: ServerDiscovery,
    private val serverRepository: ServerRepository,
    private val musicRepository: MusicRepository,
    private val settingsStore: SettingsStore,
) : ViewModel() {

    private val _state = MutableStateFlow(TvPairingUiState())
    val state: StateFlow<TvPairingUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            _state.update { it.copy(connectedUrl = settingsStore.serverUrl.first()) }
        }
        search()
    }

    fun search() {
        if (_state.value.searching) return
        viewModelScope.launch {
            _state.update { it.copy(searching = true, message = "") }
            val found = runCatching { discovery.discover() }.getOrDefault(emptyList())
            _state.update {
                it.copy(
                    searching = false,
                    servers = found,
                    // One PC on the network is the normal case — don't make the user pick from
                    // a list of one.
                    selected = it.selected ?: found.firstOrNull(),
                    message = if (found.isEmpty()) "Geen pc gevonden. Staat DebridMusic aan?" else "",
                )
            }
        }
    }

    fun select(server: DiscoveredServer) = _state.update { it.copy(selected = server, message = "") }

    fun appendDigit(digit: String) = _state.update {
        if (it.code.length >= 6) it else it.copy(code = it.code + digit, message = "")
    }

    fun deleteDigit() = _state.update {
        if (it.code.isEmpty()) it else it.copy(code = it.code.dropLast(1))
    }

    fun pair() {
        val current = _state.value
        val server = current.selected ?: return
        if (current.code.length != 6 || current.pairing) return

        viewModelScope.launch {
            _state.update { it.copy(pairing = true, message = "Koppelen…") }
            serverRepository.pair(server.baseUrl, current.code, Build.MODEL ?: "Android TV")
                .onSuccess { response ->
                    _state.update {
                        it.copy(
                            pairing = false,
                            code = "",
                            pairedName = response.name,
                            connectedUrl = server.baseUrl,
                            message = "Gekoppeld aan ${response.name}. Bibliotheek ophalen…",
                        )
                    }
                    syncNow(server.baseUrl)
                }
                .onFailure {
                    _state.update {
                        it.copy(
                            pairing = false,
                            code = "",
                            message = "Code klopt niet, of is verlopen. Vraag een nieuwe op je pc.",
                        )
                    }
                }
        }
    }

    /** Pull the library straight away — pairing that leaves an empty screen looks like a failure. */
    private suspend fun syncNow(url: String) {
        runCatching {
            val token = settingsStore.serverToken.first()
            val catalog = serverRepository.fetchCatalog()
            val count = musicRepository.syncServerLibrary(catalog, url, token)
            settingsStore.setServerLastSync(System.currentTimeMillis())
            count
        }.onSuccess { count ->
            _state.update { it.copy(trackCount = count, message = "Klaar — $count nummers.") }
        }.onFailure {
            _state.update { it.copy(message = "Gekoppeld, maar de bibliotheek ophalen lukte niet.") }
        }
    }
}
