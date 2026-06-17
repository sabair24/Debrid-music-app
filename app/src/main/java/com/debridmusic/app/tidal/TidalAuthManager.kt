package com.debridmusic.app.tidal

import android.content.Context
import com.debridmusic.app.data.local.SettingsStore
import com.tidal.sdk.auth.TidalAuth
import com.tidal.sdk.auth.model.AuthConfig
import com.tidal.sdk.auth.model.AuthResult
import com.tidal.sdk.auth.model.DeviceAuthorizationResponse
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.first
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Wraps the official Tidal SDK auth module. Uses the user's own Client ID/Secret
 * (stored on-device in SettingsStore) and the OAuth Device Login flow so a
 * subscriber can sign into their own account. Personal-use integration.
 */
@Singleton
class TidalAuthManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val settingsStore: SettingsStore,
) {
    private var auth: TidalAuth? = null

    private suspend fun instance(): TidalAuth? {
        auth?.let { return it }
        val clientId = settingsStore.tidalClientId.first()
        val clientSecret = settingsStore.tidalClientSecret.first()
        if (clientId.isBlank()) return null
        val config = AuthConfig(
            clientId = clientId,
            clientSecret = clientSecret,
            credentialsKey = "debridmusic_tidal",
            scopes = setOf("r_usr", "w_usr"),
            enableCertificatePinning = true,
        )
        return TidalAuth.getInstance(config, context).also { auth = it }
    }

    suspend fun hasClientId(): Boolean = settingsStore.tidalClientId.first().isNotBlank()

    suspend fun isLoggedIn(): Boolean =
        runCatching { instance()?.credentialsProvider?.isUserLoggedIn() == true }.getOrDefault(false)

    /** Starts device login; returns the code + verification URL to show the user. */
    suspend fun startDeviceLogin(): DeviceAuthorizationResponse? {
        val a = instance() ?: return null
        return when (val r = a.auth.initializeDeviceLogin()) {
            is AuthResult.Success -> r.data
            else -> null
        }
    }

    /** Polls until the user authorizes the code (or it expires). Returns success. */
    suspend fun completeDeviceLogin(deviceCode: String): Boolean {
        val a = instance() ?: return false
        return a.auth.finalizeDeviceLogin(deviceCode) is AuthResult.Success
    }

    suspend fun logout() {
        runCatching { instance()?.auth?.logout() }
    }

    /** Forces re-creation of the SDK instance after credentials change. */
    fun reset() { auth = null }
}
