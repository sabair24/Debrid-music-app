package com.debridmusic.app.data.local

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SettingsStore @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) {
    // ── Existing keys ─────────────────────────────────────────────────────────
    val lastFmApiKey: Flow<String> = dataStore.data.map { it[KEY_LASTFM_API_KEY] ?: "" }
    val discogsToken: Flow<String> = dataStore.data.map { it[KEY_DISCOGS_TOKEN] ?: "" }
    val torBoxApiKey: Flow<String> = dataStore.data.map { it[KEY_TORBOX_API_KEY] ?: "" }

    suspend fun setLastFmApiKey(key: String) { dataStore.edit { it[KEY_LASTFM_API_KEY] = key } }
    suspend fun setDiscogsToken(token: String) { dataStore.edit { it[KEY_DISCOGS_TOKEN] = token } }
    suspend fun setTorBoxApiKey(key: String) { dataStore.edit { it[KEY_TORBOX_API_KEY] = key } }

    // ── Discogs collection cache (synced from the user's Discogs account) ────────
    val discogsCollectionJson: Flow<String> = dataStore.data.map { it[KEY_DISCOGS_COLLECTION_JSON] ?: "" }
    val discogsLastSyncTime: Flow<Long> = dataStore.data.map { it[KEY_DISCOGS_LAST_SYNC] ?: 0L }

    suspend fun setDiscogsCollectionJson(json: String) { dataStore.edit { it[KEY_DISCOGS_COLLECTION_JSON] = json } }
    suspend fun setDiscogsLastSyncTime(millis: Long) { dataStore.edit { it[KEY_DISCOGS_LAST_SYNC] = millis } }

    // ── Last.fm scrobble ──────────────────────────────────────────────────────
    val lastFmSessionKey: Flow<String> = dataStore.data.map { it[KEY_LASTFM_SESSION_KEY] ?: "" }
    val lastFmUsername: Flow<String> = dataStore.data.map { it[KEY_LASTFM_USERNAME] ?: "" }

    // In-memory only — never persist raw passwords
    val lastFmApiSecret = MutableStateFlow("")

    suspend fun setLastFmSessionKey(key: String) { dataStore.edit { it[KEY_LASTFM_SESSION_KEY] = key } }
    suspend fun setLastFmUsername(name: String) { dataStore.edit { it[KEY_LASTFM_USERNAME] = name } }
    suspend fun setLastFmApiSecret(secret: String) { lastFmApiSecret.value = secret }

    suspend fun clearLastFmSession() {
        dataStore.edit {
            it.remove(KEY_LASTFM_SESSION_KEY)
            it.remove(KEY_LASTFM_USERNAME)
        }
        lastFmApiSecret.value = ""
    }

    // ── EQ ───────────────────────────────────────────────────────────────────
    val eqEnabled: Flow<Boolean> = dataStore.data.map { it[KEY_EQ_ENABLED] ?: false }
    val eqBandGains: Flow<String> = dataStore.data.map { it[KEY_EQ_BANDS] ?: "0,0,0,0,0" }

    suspend fun setEqEnabled(enabled: Boolean) { dataStore.edit { it[KEY_EQ_ENABLED] = enabled } }
    suspend fun setEqBandGains(csv: String) { dataStore.edit { it[KEY_EQ_BANDS] = csv } }

    // ── Cross-fade ───────────────────────────────────────────────────────────
    val crossFadeDurationMs: Flow<Int> = dataStore.data.map { it[KEY_CROSSFADE_MS] ?: 0 }

    suspend fun setCrossFadeDurationMs(ms: Int) { dataStore.edit { it[KEY_CROSSFADE_MS] = ms } }

    // ── Soulseek ──────────────────────────────────────────────────────────────
    val slskUsername: Flow<String> = dataStore.data.map { it[KEY_SLSK_USERNAME] ?: "" }
    val slskPassword: Flow<String> = dataStore.data.map { it[KEY_SLSK_PASSWORD] ?: "" }

    suspend fun setSlskUsername(v: String) { dataStore.edit { it[KEY_SLSK_USERNAME] = v } }
    suspend fun setSlskPassword(v: String) { dataStore.edit { it[KEY_SLSK_PASSWORD] = v } }

    // ── RuTracker (torrent source) ──────────────────────────────────────────────
    val ruTrackerUsername: Flow<String> = dataStore.data.map { it[KEY_RUTRACKER_USER] ?: "" }
    val ruTrackerPassword: Flow<String> = dataStore.data.map { it[KEY_RUTRACKER_PASS] ?: "" }

    suspend fun setRuTrackerUsername(v: String) { dataStore.edit { it[KEY_RUTRACKER_USER] = v } }
    suspend fun setRuTrackerPassword(v: String) { dataStore.edit { it[KEY_RUTRACKER_PASS] = v } }

    // ── Storage management ──────────────────────────────────────────────────────
    val downloadTreeUri: Flow<String> = dataStore.data.map { it[KEY_DOWNLOAD_TREE_URI] ?: "" }
    // 0 = unlimited. Default 4 GB.
    val maxDownloadBytes: Flow<Long> = dataStore.data.map { it[KEY_MAX_DOWNLOAD_BYTES] ?: (4L * 1024 * 1024 * 1024) }

    suspend fun setDownloadTreeUri(uri: String) { dataStore.edit { it[KEY_DOWNLOAD_TREE_URI] = uri } }
    suspend fun setMaxDownloadBytes(bytes: Long) { dataStore.edit { it[KEY_MAX_DOWNLOAD_BYTES] = bytes } }

    // ── Tidal (official SDK) ────────────────────────────────────────────────────
    val tidalClientId: Flow<String> = dataStore.data.map { it[KEY_TIDAL_CLIENT_ID] ?: "" }
    val tidalClientSecret: Flow<String> = dataStore.data.map { it[KEY_TIDAL_CLIENT_SECRET] ?: "" }

    suspend fun setTidalClientId(v: String) { dataStore.edit { it[KEY_TIDAL_CLIENT_ID] = v } }
    suspend fun setTidalClientSecret(v: String) { dataStore.edit { it[KEY_TIDAL_CLIENT_SECRET] = v } }

    // ── Playback (shuffle / repeat) ─────────────────────────────────────────────
    val shuffleEnabled: Flow<Boolean> = dataStore.data.map { it[KEY_SHUFFLE_ENABLED] ?: false }
    val repeatMode: Flow<Int> = dataStore.data.map { it[KEY_REPEAT_MODE] ?: 0 } // RepeatMode ordinal

    suspend fun setShuffleEnabled(enabled: Boolean) { dataStore.edit { it[KEY_SHUFFLE_ENABLED] = enabled } }
    suspend fun setRepeatMode(ordinal: Int) { dataStore.edit { it[KEY_REPEAT_MODE] = ordinal } }

    companion object {
        val KEY_LASTFM_API_KEY = stringPreferencesKey("last_fm_api_key")
        val KEY_DISCOGS_TOKEN = stringPreferencesKey("discogs_token")
        val KEY_DISCOGS_COLLECTION_JSON = stringPreferencesKey("discogs_collection_json")
        val KEY_DISCOGS_LAST_SYNC = longPreferencesKey("discogs_last_sync")
        val KEY_TORBOX_API_KEY = stringPreferencesKey("torbox_api_key")
        val KEY_LASTFM_SESSION_KEY = stringPreferencesKey("lastfm_session_key")
        val KEY_LASTFM_USERNAME = stringPreferencesKey("lastfm_username")
        val KEY_EQ_ENABLED = booleanPreferencesKey("eq_enabled")
        val KEY_EQ_BANDS = stringPreferencesKey("eq_bands")
        val KEY_CROSSFADE_MS = intPreferencesKey("crossfade_ms")
        val KEY_SLSK_USERNAME = stringPreferencesKey("slsk_username")
        val KEY_SLSK_PASSWORD = stringPreferencesKey("slsk_password")
        val KEY_RUTRACKER_USER = stringPreferencesKey("rutracker_user")
        val KEY_RUTRACKER_PASS = stringPreferencesKey("rutracker_pass")
        val KEY_SHUFFLE_ENABLED = booleanPreferencesKey("shuffle_enabled")
        val KEY_REPEAT_MODE = intPreferencesKey("repeat_mode")
        val KEY_TIDAL_CLIENT_ID = stringPreferencesKey("tidal_client_id")
        val KEY_TIDAL_CLIENT_SECRET = stringPreferencesKey("tidal_client_secret")
        val KEY_DOWNLOAD_TREE_URI = stringPreferencesKey("download_tree_uri")
        val KEY_MAX_DOWNLOAD_BYTES = longPreferencesKey("max_download_bytes")
    }
}
