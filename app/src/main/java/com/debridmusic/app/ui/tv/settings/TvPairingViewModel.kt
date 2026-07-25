package com.debridmusic.app.ui.tv.settings

import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.cloud.CloudAuthException
import com.debridmusic.app.cloud.CloudConnect
import com.debridmusic.app.cloud.CloudSession
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
    // ── Signing in ─────────────────────────────────────────────────────────
    val email: String = "",
    val password: String = "",
    val signingIn: Boolean = false,
    val register: Boolean = false,
    val signedIn: Boolean = false,
    val signInMessage: String = "",
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
    private val cloudSession: CloudSession,
    private val cloudConnect: CloudConnect,
) : ViewModel() {

    private val _state = MutableStateFlow(TvPairingUiState())
    val state: StateFlow<TvPairingUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            _state.update { it.copy(connectedUrl = settingsStore.serverUrl.first()) }
            // A session saved on this device. If it restores, connecting needs no typing at all —
            // which on a TV remote is the whole point.
            if (runCatching { cloudSession.restore() }.getOrDefault(false)) {
                _state.update { it.copy(signedIn = true) }
                connectViaCloud()
            }
        }
        search()
    }

    fun setEmail(v: String) = _state.update { it.copy(email = v, signInMessage = "") }
    fun setPassword(v: String) = _state.update { it.copy(password = v, signInMessage = "") }
    fun toggleRegister() = _state.update { it.copy(register = !it.register, signInMessage = "") }

    /**
     * Sign in, then let the PC hand this device its own token.
     *
     * Replaces the six digits, and is worth more than the saved typing: the code gave every device
     * the same shared secret, so a single device could never be cut off on its own.
     */
    fun signIn() {
        val s = _state.value
        if (s.signingIn) return
        if (s.email.isBlank() || s.password.isBlank()) {
            _state.update { it.copy(signInMessage = "Vul je e-mailadres en wachtwoord in.") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(signingIn = true, signInMessage = "") }
            val result = runCatching {
                if (s.register) cloudSession.register(s.email, s.password)
                else cloudSession.signIn(s.email, s.password)
            }
            if (result.isFailure) {
                val cause = result.exceptionOrNull()
                // A CloudAuthException already reads as a sentence; prefixing it would produce
                // "Inloggen mislukte: E-mailadres of wachtwoord klopt niet." Anything else is a
                // technical message that needs the prefix to make sense at all.
                val text = when {
                    cause is CloudAuthException -> cause.message.orEmpty()
                    else -> "Inloggen mislukte: ${cause?.message ?: "onbekende fout"}"
                }
                _state.update { it.copy(signingIn = false, signInMessage = text) }
                return@launch
            }
            _state.update { it.copy(signedIn = true, password = "") }
            connectViaCloud()
        }
    }

    private suspend fun connectViaCloud() {
        _state.update { it.copy(signingIn = true, signInMessage = "Toegang aanvragen bij je pc…") }
        when (val r = runCatching { cloudConnect.connect() }.getOrNull()) {
            is CloudConnect.Result.Connected -> {
                _state.update {
                    it.copy(
                        signingIn = false,
                        connectedUrl = r.url,
                        signInMessage = "Verbonden met ${r.serverName}.",
                    )
                }
                // The same pull the pairing path does. Connecting to a PC and then showing an
                // empty screen looks like a failure, whichever way you got there.
                syncNow(r.url)
            }
            is CloudConnect.Result.NoServer -> _state.update {
                it.copy(
                    signingIn = false,
                    signInMessage = "Nog geen pc onder dit account. Log op je pc in met hetzelfde account.",
                )
            }
            is CloudConnect.Result.Waiting -> _state.update {
                it.copy(
                    signingIn = false,
                    signInMessage = "${r.serverName} heeft nog niet geantwoord. Zet hem aan — je aanvraag blijft staan.",
                )
            }
            is CloudConnect.Result.Unreachable -> _state.update {
                it.copy(
                    signingIn = false,
                    signInMessage = "${r.serverName} gaf toegang, maar is op dit netwerk niet bereikbaar.",
                )
            }
            null -> _state.update {
                it.copy(signingIn = false, signInMessage = "Verbinden mislukte. Probeer het opnieuw.")
            }
        }
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
