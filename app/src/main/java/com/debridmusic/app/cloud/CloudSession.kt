package com.debridmusic.app.cloud

import android.os.Build
import com.debridmusic.app.data.local.SettingsStore
import com.google.gson.Gson
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import retrofit2.HttpException
import java.io.IOException
import java.security.SecureRandom
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Carries the sentence to put in front of the user, with Firebase's own code kept alongside for the
 * log. Mirrors `CloudAuthException` in the Flutter app so the two say the same thing in the same
 * words on the same failure.
 */
class CloudAuthException(
    message: String,
    val code: String = "",
    cause: Throwable? = null,
) : Exception(message, cause)

/**
 * Firebase deliberately blurs "no such account" and "wrong password" into one code so an attacker
 * cannot use the login form to discover which addresses exist. Say the same thing for both rather
 * than leaking the difference back in the translation.
 */
private fun dutch(code: String, status: Int): String = when (code.substringBefore(" : ")) {
    "EMAIL_NOT_FOUND", "INVALID_PASSWORD", "INVALID_LOGIN_CREDENTIALS" ->
        "E-mailadres of wachtwoord klopt niet."
    "EMAIL_EXISTS" -> "Er bestaat al een account met dit e-mailadres."
    "WEAK_PASSWORD" -> "Kies een wachtwoord van minstens zes tekens."
    "INVALID_EMAIL" -> "Dat is geen geldig e-mailadres."
    "USER_DISABLED" -> "Dit account is uitgeschakeld."
    "TOO_MANY_ATTEMPTS_TRY_LATER" ->
        "Te veel pogingen. Probeer het over een paar minuten opnieuw."
    "TOKEN_EXPIRED", "USER_NOT_FOUND", "INVALID_REFRESH_TOKEN" ->
        "Je sessie is verlopen. Log opnieuw in."
    "OPERATION_NOT_ALLOWED" ->
        "Inloggen met e-mail staat uit in dit Firebase-project. " +
            "Zet het aan onder Authentication → Sign-in method."
    else -> "Firebase antwoordde met $status" + if (code.isBlank()) "." else " ($code)."
}

/**
 * Signing in, and getting this device its own key to the PC.
 *
 * Replaces the six digits. What that buys is not only convenience: the code handed every device
 * the same shared secret, so a single device could never be cut off on its own. Here the account
 * says who you are, the PC issues a token for this device alone, and revoking it on the PC stops
 * this device and nothing else.
 *
 * The pairing code still works and is still reachable. A network without internet, or a Firebase
 * having a bad day, must not leave you unable to reach a machine in the next room.
 */
@Singleton
class CloudSession @Inject constructor(
    private val authApi: CloudAuthApi,
    private val tokenApi: CloudTokenApi,
    private val db: CloudFirestoreApi,
    private val settingsStore: SettingsStore,
) {
    private var idToken: String = ""
    private var idTokenExpiry: Long = 0
    var uid: String = ""
        private set

    val isSignedIn: Boolean get() = uid.isNotBlank()

    /** Restore a session saved on this device. False when there is nothing to restore. */
    suspend fun restore(): Boolean {
        val refresh = settingsStore.cloudRefreshToken.first()
        if (refresh.isBlank()) return false
        return runCatching { refreshNow(refresh) }.isSuccess
    }

    suspend fun signIn(email: String, password: String) {
        val res = explained { authApi.signIn(CloudConfig.API_KEY, AuthRequest(email.trim(), password)) }
        adopt(res.idToken, res.refreshToken, res.localId, res.expiresIn)
    }

    suspend fun register(email: String, password: String) {
        val res = explained { authApi.signUp(CloudConfig.API_KEY, AuthRequest(email.trim(), password)) }
        adopt(res.idToken, res.refreshToken, res.localId, res.expiresIn)
    }

    /**
     * Run an Identity Toolkit call and turn a refusal into a sentence.
     *
     * Retrofit's own message for a rejected sign-in is "HTTP 400", which is true and useless: it
     * looks the same whether you mistyped your password, the account does not exist, or e-mail
     * sign-in is switched off in the Firebase console. The reason is in the body, so read it.
     */
    private suspend fun <T> explained(call: suspend () -> T): T = try {
        call()
    } catch (e: HttpException) {
        val body = runCatching { e.response()?.errorBody()?.string() }.getOrNull().orEmpty()
        val code = runCatching { Gson().fromJson(body, AuthError::class.java) }
            .getOrNull()?.error?.message.orEmpty()
        throw CloudAuthException(dutch(code, e.code()), code)
    } catch (e: IOException) {
        // No internet, or DNS is down. Distinct from a refusal on purpose: the answer is to check
        // the network, not the password.
        throw CloudAuthException("Geen verbinding met Firebase. Controleer je netwerk.", "NETWORK", e)
    }

    suspend fun signOut() {
        idToken = ""
        idTokenExpiry = 0
        uid = ""
        settingsStore.setCloudRefreshToken("")
        settingsStore.setCloudUid("")
    }

    private suspend fun adopt(id: String, refresh: String, user: String, expiresIn: String) {
        require(id.isNotBlank() && user.isNotBlank()) { "Firebase gaf geen sessie terug" }
        idToken = id
        uid = user
        idTokenExpiry = System.currentTimeMillis() + (expiresIn.toLongOrNull() ?: 3600L) * 1000
        settingsStore.setCloudRefreshToken(refresh)
        settingsStore.setCloudUid(user)
    }

    private suspend fun refreshNow(refresh: String) {
        val res = tokenApi.refresh(CloudConfig.API_KEY, "refresh_token", refresh)
        require(res.idToken.isNotBlank()) { "Sessie verlopen" }
        idToken = res.idToken
        uid = res.userId
        idTokenExpiry = System.currentTimeMillis() + (res.expiresIn.toLongOrNull() ?: 3600L) * 1000
        if (res.refreshToken.isNotBlank()) settingsStore.setCloudRefreshToken(res.refreshToken)
        settingsStore.setCloudUid(res.userId)
    }

    /**
     * A bearer header with a token that is good right now.
     *
     * Refreshed a minute early on purpose: a token that expires between this check and the request
     * arriving fails as a 401, which reads like a wrong password rather than a clock.
     */
    private suspend fun auth(): String {
        if (idToken.isBlank() || System.currentTimeMillis() > idTokenExpiry - 60_000) {
            val refresh = settingsStore.cloudRefreshToken.first()
            require(refresh.isNotBlank()) { "Niet ingelogd" }
            refreshNow(refresh)
        }
        return "Bearer $idToken"
    }

    /** The PCs signed in under this account. */
    suspend fun servers(): List<CloudServer> {
        if (!isSignedIn) return emptyList()
        val res = runCatching { db.list("users/$uid/servers", auth(), 300) }.getOrNull() ?: return emptyList()
        return res.documents.mapNotNull { CloudServer.from(it) }
            .sortedByDescending { it.lastSeen }
    }

    /**
     * Ask a PC for access, and return the token once it has been granted.
     *
     * Null while still waiting, which is the ordinary state when the PC is simply switched off —
     * the request stays on file and the PC picks it up when it wakes.
     */
    suspend fun requestAccess(serverId: String): String? {
        if (!isSignedIn) return null
        val deviceId = deviceId()
        val path = "users/$uid/servers/$serverId/grants/$deviceId"

        val existing = runCatching { db.get(path, auth()) }.getOrNull()
        when (existing?.str("status")) {
            "granted" -> existing.str("token")?.takeIf { it.isNotBlank() }?.let { return it }
            "revoked" -> return null
        }

        if (existing == null || existing.str("status") != "pending") {
            // Deliberately without a token field: the rules refuse a client that tries to hand
            // itself one, so a bug here fails loudly instead of quietly granting access.
            val url = CloudConfig.FIRESTORE_BASE + path +
                "?updateMask.fieldPaths=status" +
                "&updateMask.fieldPaths=deviceName" +
                "&updateMask.fieldPaths=platform"
            runCatching {
                db.patch(
                    url, auth(),
                    FireDocument(
                        fields = mapOf(
                            "status" to FireValue.of("pending"),
                            "deviceName" to FireValue.of(deviceName()),
                            "platform" to FireValue.of("android"),
                        ),
                    ),
                )
            }
        }
        return null
    }

    /**
     * Wait for the PC to answer. Polls rather than streams: Firestore's REST API has no listener,
     * and a request every two seconds for a minute is far cheaper than keeping a socket open on a
     * TV box that is mostly idle.
     */
    suspend fun awaitAccess(serverId: String, attempts: Int = 30): String? {
        repeat(attempts) {
            requestAccess(serverId)?.let { return it }
            delay(2000)
        }
        return null
    }

    /** This device's id, generated once and kept. Revoking access is per device, so it must last. */
    suspend fun deviceId(): String {
        val existing = settingsStore.cloudDeviceId.first()
        if (existing.isNotBlank()) return existing
        val bytes = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val id = bytes.joinToString("") { "%02x".format(it) }
        settingsStore.setCloudDeviceId(id)
        return id
    }

    /** What the PC lists this device as — its own name, because that is what you look for. */
    fun deviceName(): String {
        val model = listOf(Build.MANUFACTURER, Build.MODEL)
            .filter { !it.isNullOrBlank() }
            .joinToString(" ")
            .trim()
        return model.ifBlank { "Android" }
    }
}
