package com.debridmusic.app.cloud

import com.google.gson.annotations.SerializedName

/**
 * Firebase over REST, the same way the Windows, Mac and iPad app does it.
 *
 * No Firebase SDK on purpose. The SDK would pull in Google Play services, which a Shield has but a
 * plain Android TV box may not, and it wants a `google-services.json` per build variant. Two HTTP
 * endpoints are the whole dependency instead, and the wire format is identical across all four
 * platforms — so a change is one shape to keep in step, not four.
 */

// ── Identity Toolkit: signing in ────────────────────────────────────────────

data class AuthRequest(
    val email: String,
    val password: String,
    val returnSecureToken: Boolean = true,
)

data class AuthResponse(
    @SerializedName("idToken") val idToken: String = "",
    @SerializedName("refreshToken") val refreshToken: String = "",
    @SerializedName("localId") val localId: String = "",
    @SerializedName("expiresIn") val expiresIn: String = "3600",
)

/**
 * What Firebase sends back on a refusal. The reason lives in `error.message` as a shouty constant
 * — `INVALID_LOGIN_CREDENTIALS` and the like — and without reading it there is nothing left to tell
 * someone except the status code, which explains nothing.
 */
data class AuthError(
    @SerializedName("error") val error: AuthErrorBody? = null,
)

data class AuthErrorBody(
    @SerializedName("message") val message: String = "",
)

data class RefreshResponse(
    @SerializedName("id_token") val idToken: String = "",
    @SerializedName("refresh_token") val refreshToken: String = "",
    @SerializedName("user_id") val userId: String = "",
    @SerializedName("expires_in") val expiresIn: String = "3600",
)

// ── Firestore: typed values ─────────────────────────────────────────────────
//
// Firestore's REST API wraps every value in its type. Verbose, but it means a number stays a
// number across four languages instead of becoming a string somewhere along the way.

data class FireValue(
    @SerializedName("stringValue") val stringValue: String? = null,
    @SerializedName("integerValue") val integerValue: String? = null,
    @SerializedName("doubleValue") val doubleValue: Double? = null,
    @SerializedName("booleanValue") val booleanValue: Boolean? = null,
    @SerializedName("timestampValue") val timestampValue: String? = null,
    @SerializedName("nullValue") val nullValue: String? = null,
    @SerializedName("arrayValue") val arrayValue: FireArray? = null,
    @SerializedName("mapValue") val mapValue: FireMap? = null,
) {
    val asString: String? get() = stringValue
    val asLong: Long? get() = integerValue?.toLongOrNull() ?: doubleValue?.toLong()
    val asBool: Boolean? get() = booleanValue
    val asList: List<FireValue> get() = arrayValue?.values ?: emptyList()

    companion object {
        fun of(v: String) = FireValue(stringValue = v)
        fun of(v: Long) = FireValue(integerValue = v.toString())
        fun of(v: Boolean) = FireValue(booleanValue = v)
        fun ofStrings(v: List<String>) = FireValue(arrayValue = FireArray(v.map { of(it) }))
    }
}

data class FireArray(@SerializedName("values") val values: List<FireValue> = emptyList())

data class FireMap(@SerializedName("fields") val fields: Map<String, FireValue> = emptyMap())

data class FireDocument(
    @SerializedName("name") val name: String? = null,
    @SerializedName("fields") val fields: Map<String, FireValue> = emptyMap(),
) {
    /** The last path segment — the document id, which the full name buries. */
    val id: String get() = name?.substringAfterLast('/') ?: ""

    fun str(key: String): String? = fields[key]?.asString
    fun long(key: String): Long? = fields[key]?.asLong
    fun bool(key: String): Boolean? = fields[key]?.asBool
    fun strings(key: String): List<String> = fields[key]?.asList?.mapNotNull { it.asString } ?: emptyList()

    /**
     * A Firestore timestamp, as epoch millis. It arrives as RFC-3339 text, not a number — reading
     * it as an integer yields null and makes every PC look like it has never been seen.
     */
    fun millis(key: String): Long {
        val raw = fields[key]?.timestampValue ?: return fields[key]?.asLong ?: 0L
        return try {
            java.time.Instant.parse(raw).toEpochMilli()
        } catch (_: Exception) {
            0L
        }
    }
}

data class FireListResponse(
    @SerializedName("documents") val documents: List<FireDocument> = emptyList(),
)

// ── What the PC publishes about itself ──────────────────────────────────────

data class CloudServer(
    val id: String,
    val name: String,
    val urls: List<String>,
    val online: Boolean,
    val lastSeen: Long,
    val trackCount: Long,
) {
    /**
     * Seen recently enough to be worth waiting for. The PC writes every thirty seconds, so three
     * minutes is several missed beats — a machine that is merely busy still counts as awake.
     */
    val isFresh: Boolean
        get() = lastSeen > 0 && System.currentTimeMillis() - lastSeen < 3 * 60 * 1000

    companion object {
        fun from(doc: FireDocument): CloudServer? {
            val id = doc.id.ifBlank { return null }
            return CloudServer(
                id = id,
                name = doc.str("name") ?: id,
                urls = doc.strings("urls"),
                online = doc.bool("online") ?: false,
                // lastSeenAt, not lastSeen: the name the PC actually writes.
                lastSeen = doc.millis("lastSeenAt"),
                trackCount = doc.long("trackCount") ?: 0L,
            )
        }
    }
}
