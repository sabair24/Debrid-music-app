package com.debridmusic.server

import java.io.File
import java.util.Properties

/**
 * Small persistent key/value store for server-side credentials & options
 * (TorBox API key, Soulseek/RuTracker logins, Discogs token, Last.fm key, …).
 * Backed by a properties file in the data dir. Secrets never leave the box:
 * the API only ever reports whether a key is *set*, not its value.
 */
class ServerSettings(private val file: File) {
    private val props = Properties()

    init {
        if (file.isFile) runCatching { file.inputStream().use { props.load(it) } }
    }

    companion object {
        // Known keys (mirrors the Android app's SettingsStore names where sensible).
        const val TORBOX_API_KEY = "torbox_api_key"
        const val SOULSEEK_USER = "soulseek_user"
        const val SOULSEEK_PASS = "soulseek_pass"
        const val RUTRACKER_USER = "rutracker_user"
        const val RUTRACKER_PASS = "rutracker_pass"
        const val DISCOGS_TOKEN = "discogs_token"
        const val LASTFM_KEY = "lastfm_key"

        /** Keys the web Settings UI manages. */
        val UI_KEYS = listOf(
            TORBOX_API_KEY, SOULSEEK_USER, SOULSEEK_PASS,
            RUTRACKER_USER, RUTRACKER_PASS, DISCOGS_TOKEN, LASTFM_KEY,
        )
    }

    @Synchronized
    fun get(key: String): String? = props.getProperty(key)?.trim()?.takeIf { it.isNotEmpty() }

    @Synchronized
    fun set(updates: Map<String, String?>) {
        updates.forEach { (k, v) ->
            if (v.isNullOrBlank()) props.remove(k) else props.setProperty(k, v.trim())
        }
        runCatching { file.outputStream().use { props.store(it, "DebridMusic server settings") } }
    }

    /** For the UI: which known keys currently have a value (never exposes the value). */
    @Synchronized
    fun presence(): Map<String, Boolean> = UI_KEYS.associateWith { get(it) != null }
}
