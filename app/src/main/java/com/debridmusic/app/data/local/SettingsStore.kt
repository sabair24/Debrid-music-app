package com.debridmusic.app.data.local

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SettingsStore @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) {
    val lastFmApiKey: Flow<String> = dataStore.data.map { it[KEY_LASTFM_API_KEY] ?: "" }
    val discogsToken: Flow<String> = dataStore.data.map { it[KEY_DISCOGS_TOKEN] ?: "" }
    val torBoxApiKey: Flow<String> = dataStore.data.map { it[KEY_TORBOX_API_KEY] ?: "" }

    suspend fun setLastFmApiKey(key: String) {
        dataStore.edit { it[KEY_LASTFM_API_KEY] = key }
    }

    suspend fun setDiscogsToken(token: String) {
        dataStore.edit { it[KEY_DISCOGS_TOKEN] = token }
    }

    suspend fun setTorBoxApiKey(key: String) {
        dataStore.edit { it[KEY_TORBOX_API_KEY] = key }
    }

    companion object {
        val KEY_LASTFM_API_KEY = stringPreferencesKey("last_fm_api_key")
        val KEY_DISCOGS_TOKEN = stringPreferencesKey("discogs_token")
        val KEY_TORBOX_API_KEY = stringPreferencesKey("torbox_api_key")
    }
}
