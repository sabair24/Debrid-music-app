package com.debridmusic.app.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.remote.DiscogsAuthInterceptor
import com.debridmusic.app.data.remote.api.DiscogsApi
import com.debridmusic.app.data.remote.dto.TorBoxUser
import com.debridmusic.app.data.repository.DiscogsRepository
import com.debridmusic.app.metadata.EnrichmentProgress
import com.debridmusic.app.metadata.MetadataEnricher
import com.debridmusic.app.player.EqController
import com.debridmusic.app.player.ScrobbleManager
import com.debridmusic.app.soulseek.SoulseekRepository
import com.debridmusic.app.torbox.TorBoxAuthInterceptor
import com.debridmusic.app.torbox.TorBoxRepository
import com.debridmusic.app.update.UpdateRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SettingsUiState(
    val lastFmApiKey: String = "",
    val discogsToken: String = "",
    val discogsValidating: Boolean = false,
    val discogsUsername: String? = null,
    val discogsError: String? = null,
    val discogsSyncing: Boolean = false,
    val discogsSyncResult: String? = null,
    val torBoxApiKey: String = "",
    val isEnriching: Boolean = false,
    val enrichProgress: EnrichmentProgress? = null,
    val enrichResult: String? = null,
    val torBoxUser: TorBoxUser? = null,
    val torBoxValidating: Boolean = false,
    val torBoxError: String? = null,
    // Soulseek
    val slskUsername: String = "",
    val slskPassword: String = "",
    // RuTracker (torrent source)
    val ruTrackerUsername: String = "",
    val ruTrackerPassword: String = "",
    val slskVerifying: Boolean = false,
    val slskLoggedIn: Boolean = false,
    val slskError: String? = null,
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
    // App updates (GitHub Releases)
    val updateChecking: Boolean = false,
    val updateAvailable: Boolean = false,
    val updateVersion: String = "",
    val updateNotes: String = "",
    val updateApkUrl: String? = null,
    val updateUpToDate: Boolean = false,
    val updateDownloading: Boolean = false,
    val updateProgress: Float = 0f,
    val updateError: String? = null,
    // Storage
    val downloadsSizeBytes: Long = 0L,
    val cacheSizeBytes: Long = 0L,
    val maxDownloadBytes: Long = 0L,
    val downloadFolder: String = "App-opslag (standaard)",
    // Tidal
    val tidalClientId: String = "",
    val tidalClientSecret: String = "",
    val tidalLoggedIn: Boolean = false,
    val tidalBusy: Boolean = false,
    val tidalUserCode: String? = null,
    val tidalVerifyUrl: String? = null,
    val tidalDeviceCode: String? = null,
    val tidalError: String? = null,
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settingsStore: SettingsStore,
    private val metadataEnricher: MetadataEnricher,
    private val torBoxRepository: TorBoxRepository,
    private val torBoxAuthInterceptor: TorBoxAuthInterceptor,
    private val discogsApi: DiscogsApi,
    private val discogsAuthInterceptor: DiscogsAuthInterceptor,
    private val discogsRepository: DiscogsRepository,
    private val soulseekRepository: SoulseekRepository,
    private val updateRepository: UpdateRepository,
    private val offlineDownloadManager: com.debridmusic.app.download.OfflineDownloadManager,
    private val tidalAuthManager: com.debridmusic.app.tidal.TidalAuthManager,
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
            combine(settingsStore.slskUsername, settingsStore.slskPassword) { u, p -> u to p }
                .collect { (u, p) -> _state.update { it.copy(slskUsername = u, slskPassword = p) } }
        }
        viewModelScope.launch {
            combine(settingsStore.ruTrackerUsername, settingsStore.ruTrackerPassword) { u, p -> u to p }
                .collect { (u, p) -> _state.update { it.copy(ruTrackerUsername = u, ruTrackerPassword = p) } }
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
        viewModelScope.launch {
            combine(settingsStore.maxDownloadBytes, settingsStore.downloadTreeUri) { max, tree -> max to tree }
                .collect { (max, tree) ->
                    _state.update {
                        it.copy(
                            maxDownloadBytes = max,
                            downloadFolder = if (tree.isBlank()) "App-opslag (standaard)" else folderNameFromTreeUri(tree),
                        )
                    }
                }
        }
        refreshStorage()
        viewModelScope.launch {
            val id = settingsStore.tidalClientId.first()
            val secret = settingsStore.tidalClientSecret.first()
            _state.update { it.copy(tidalClientId = id, tidalClientSecret = secret) }
            if (id.isNotBlank()) _state.update { it.copy(tidalLoggedIn = tidalAuthManager.isLoggedIn()) }
        }
        // Quietly check for an update when Settings opens.
        checkForUpdate(silent = true)
    }

    // ── Tidal ────────────────────────────────────────────────────────────────────
    fun setTidalClientId(v: String) = _state.update { it.copy(tidalClientId = v) }
    fun setTidalClientSecret(v: String) = _state.update { it.copy(tidalClientSecret = v) }

    fun saveTidalCreds() {
        viewModelScope.launch {
            settingsStore.setTidalClientId(_state.value.tidalClientId.trim())
            settingsStore.setTidalClientSecret(_state.value.tidalClientSecret.trim())
            tidalAuthManager.reset()
            _state.update { it.copy(tidalLoggedIn = tidalAuthManager.isLoggedIn(), tidalError = null) }
        }
    }

    fun startTidalLogin() {
        _state.update { it.copy(tidalBusy = true, tidalError = null) }
        viewModelScope.launch {
            // Persist creds first so the SDK initializes with them.
            settingsStore.setTidalClientId(_state.value.tidalClientId.trim())
            settingsStore.setTidalClientSecret(_state.value.tidalClientSecret.trim())
            tidalAuthManager.reset()
            val resp = runCatching { tidalAuthManager.startDeviceLogin() }.getOrNull()
            if (resp == null) {
                val why = tidalAuthManager.lastError
                _state.update { it.copy(tidalBusy = false, tidalError = "Login niet gestart: ${why ?: "controleer Client ID/Secret"}") }
            } else {
                _state.update {
                    it.copy(
                        tidalBusy = false,
                        tidalUserCode = resp.userCode,
                        tidalVerifyUrl = resp.verificationUriComplete?.takeIf { it.isNotBlank() } ?: resp.verificationUri,
                        tidalDeviceCode = resp.deviceCode,
                    )
                }
            }
        }
    }

    fun completeTidalLogin() {
        val code = _state.value.tidalDeviceCode ?: return
        _state.update { it.copy(tidalBusy = true, tidalError = null) }
        viewModelScope.launch {
            val ok = runCatching { tidalAuthManager.completeDeviceLogin(code) }.getOrDefault(false)
            _state.update {
                it.copy(
                    tidalBusy = false,
                    tidalLoggedIn = ok,
                    tidalUserCode = if (ok) null else it.tidalUserCode,
                    tidalDeviceCode = if (ok) null else it.tidalDeviceCode,
                    tidalError = if (ok) null else "Login niet voltooid — autoriseer eerst de code en probeer opnieuw.",
                )
            }
        }
    }

    // ── RuTracker ────────────────────────────────────────────────────────────────
    fun setRuTrackerUsername(v: String) = _state.update { it.copy(ruTrackerUsername = v) }
    fun setRuTrackerPassword(v: String) = _state.update { it.copy(ruTrackerPassword = v) }
    fun saveRuTracker() {
        viewModelScope.launch {
            settingsStore.setRuTrackerUsername(_state.value.ruTrackerUsername.trim())
            settingsStore.setRuTrackerPassword(_state.value.ruTrackerPassword)
        }
    }

    fun tidalLogout() {
        viewModelScope.launch {
            tidalAuthManager.logout()
            _state.update { it.copy(tidalLoggedIn = false, tidalUserCode = null, tidalDeviceCode = null) }
        }
    }

    // ── Storage management ──────────────────────────────────────────────────────
    fun refreshStorage() {
        viewModelScope.launch {
            val downloads = offlineDownloadManager.downloadsSizeBytes()
            val cache = offlineDownloadManager.cacheSizeBytes()
            _state.update { it.copy(downloadsSizeBytes = downloads, cacheSizeBytes = cache) }
        }
    }

    fun setMaxDownloadBytes(bytes: Long) {
        viewModelScope.launch { settingsStore.setMaxDownloadBytes(bytes); offlineDownloadManager.enforceQuota(); refreshStorage() }
    }

    fun setDownloadTreeUri(uri: String) {
        viewModelScope.launch { settingsStore.setDownloadTreeUri(uri) }
    }

    fun clearDownloads() {
        viewModelScope.launch { offlineDownloadManager.clearAllDownloads(); refreshStorage() }
    }

    fun clearCache() {
        offlineDownloadManager.clearCache(); refreshStorage()
    }

    private fun folderNameFromTreeUri(uri: String): String =
        uri.substringAfterLast("%3A").substringAfterLast('/').ifBlank { "Gekozen map" }

    // ── App updates ────────────────────────────────────────────────────────────
    fun checkForUpdate(silent: Boolean = false) {
        if (_state.value.updateChecking || _state.value.updateDownloading) return
        _state.update { it.copy(updateChecking = true, updateError = null, updateUpToDate = false) }
        viewModelScope.launch {
            updateRepository.check()
                .onSuccess { info ->
                    _state.update {
                        it.copy(
                            updateChecking = false,
                            updateAvailable = info.available,
                            updateVersion = info.versionLabel,
                            updateNotes = info.notes,
                            updateApkUrl = info.apkUrl,
                            updateUpToDate = !info.available,
                        )
                    }
                }
                .onFailure { e ->
                    _state.update {
                        it.copy(updateChecking = false, updateError = if (silent) null else (e.message ?: "Controle mislukt"))
                    }
                }
        }
    }

    fun downloadUpdate() {
        val url = _state.value.updateApkUrl ?: return
        if (_state.value.updateDownloading) return
        _state.update { it.copy(updateDownloading = true, updateProgress = 0f, updateError = null) }
        viewModelScope.launch {
            runCatching {
                updateRepository.downloadAndInstall(url) { p ->
                    _state.update { it.copy(updateProgress = p) }
                }
            }.onSuccess {
                _state.update { it.copy(updateDownloading = false) }
            }.onFailure { e ->
                _state.update { it.copy(updateDownloading = false, updateError = e.message ?: "Update mislukt") }
            }
        }
    }

    fun setLastFmApiKey(key: String) = _state.update { it.copy(lastFmApiKey = key) }
    fun setDiscogsToken(token: String) =
        _state.update { it.copy(discogsToken = token, discogsUsername = null, discogsError = null) }
    fun setTorBoxApiKey(key: String) = _state.update { it.copy(torBoxApiKey = key, torBoxUser = null, torBoxError = null) }

    // Saves + verifies the Discogs token against /oauth/identity so the user gets an
    // immediate "valid, logged in as X" confirmation instead of guessing.
    fun validateDiscogsToken() {
        val token = _state.value.discogsToken.trim()
        _state.update { it.copy(discogsValidating = true, discogsUsername = null, discogsError = null) }
        viewModelScope.launch {
            settingsStore.setDiscogsToken(token)
            discogsAuthInterceptor.token = token
            if (token.isBlank()) {
                _state.update { it.copy(discogsValidating = false, discogsError = "Voer eerst een token in") }
                return@launch
            }
            runCatching { discogsApi.identity() }
                .onSuccess { id ->
                    _state.update { it.copy(discogsValidating = false, discogsUsername = id.username ?: "onbekend") }
                }
                .onFailure {
                    _state.update { it.copy(discogsValidating = false, discogsError = "Token ongeldig of netwerkfout") }
                }
        }
    }

    // Syncs the user's Discogs collection into the local cache (shown in Library → Discogs).
    fun syncDiscogsCollection() {
        if (_state.value.discogsSyncing) return
        _state.update { it.copy(discogsSyncing = true, discogsError = null, discogsSyncResult = null) }
        viewModelScope.launch {
            settingsStore.setDiscogsToken(_state.value.discogsToken.trim())
            discogsRepository.fetchAndCacheCollection(System.currentTimeMillis())
                .onSuccess { count ->
                    _state.update { it.copy(discogsSyncing = false, discogsSyncResult = "$count albums gesynchroniseerd") }
                }
                .onFailure { e ->
                    _state.update { it.copy(discogsSyncing = false, discogsError = e.message ?: "Sync mislukt") }
                }
        }
    }

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

    fun setSlskUsername(v: String) =
        _state.update { it.copy(slskUsername = v, slskLoggedIn = false, slskError = null) }
    fun setSlskPassword(v: String) =
        _state.update { it.copy(slskPassword = v, slskLoggedIn = false, slskError = null) }

    // Saves the credentials AND verifies them against the Soulseek server in one
    // step, so the user gets an immediate "logged in" confirmation and never has
    // to guess whether the save worked.
    fun saveSlskCredentials() {
        val u = _state.value.slskUsername.trim()
        val p = _state.value.slskPassword
        if (u.isBlank() || p.isBlank()) return
        _state.update { it.copy(slskVerifying = true, slskLoggedIn = false, slskError = null) }
        viewModelScope.launch {
            settingsStore.setSlskUsername(u)
            settingsStore.setSlskPassword(p)
            soulseekRepository.testLogin(u, p)
                .onSuccess {
                    _state.update { it.copy(slskVerifying = false, slskLoggedIn = true, slskError = null) }
                }
                .onFailure { e ->
                    _state.update { it.copy(slskVerifying = false, slskLoggedIn = false, slskError = e.message ?: "Inloggen mislukt") }
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
