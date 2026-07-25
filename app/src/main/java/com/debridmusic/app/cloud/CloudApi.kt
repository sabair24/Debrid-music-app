package com.debridmusic.app.cloud

import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.Url

/** Which Firebase project. Same values as the Flutter app — one account across every device. */
object CloudConfig {
    const val PROJECT_ID = "debridmusic-app"

    /**
     * Not a secret. A Firebase web API key identifies a project and grants nothing on its own;
     * Google publishes it in every web app that uses Firebase. What protects the library is the
     * Firestore rule that a document under users/{uid} is readable only by that uid.
     */
    const val API_KEY = "AIzaSyB48pQ7Bp9AeRSViAMA5TC2ZBDV0JFnDRE"

    const val AUTH_BASE = "https://identitytoolkit.googleapis.com/v1/"
    const val TOKEN_BASE = "https://securetoken.googleapis.com/v1/"
    const val FIRESTORE_BASE =
        "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/"
}

interface CloudAuthApi {
    // No default arguments anywhere in these interfaces, on purpose. Retrofit builds a dynamic
    // proxy, and Kotlin implements defaults through a synthetic $default helper — a combination
    // that fails at runtime rather than at compile time, which is the worst place to find out.
    @POST("accounts:signInWithPassword")
    suspend fun signIn(
        @Query("key") key: String,
        @Body body: AuthRequest,
    ): AuthResponse

    @POST("accounts:signUp")
    suspend fun signUp(
        @Query("key") key: String,
        @Body body: AuthRequest,
    ): AuthResponse
}

interface CloudTokenApi {
    /**
     * Form-encoded, not JSON: this endpoint is the odd one out in Firebase's REST surface and
     * refuses a JSON body.
     */
    @retrofit2.http.FormUrlEncoded
    @POST("token")
    suspend fun refresh(
        @Query("key") key: String,
        @retrofit2.http.Field("grant_type") grantType: String,
        @retrofit2.http.Field("refresh_token") refreshToken: String,
    ): RefreshResponse
}

interface CloudFirestoreApi {
    @GET("{path}")
    suspend fun get(
        @Path("path", encoded = true) path: String,
        @Header("Authorization") auth: String,
    ): FireDocument

    @GET("{path}")
    suspend fun list(
        @Path("path", encoded = true) path: String,
        @Header("Authorization") auth: String,
        @Query("pageSize") pageSize: Int,
    ): FireListResponse

    /**
     * updateMask keeps this a merge rather than a replace. Without it, writing "status" would
     * erase the token the PC put next to it — and a device would grant itself an empty key.
     */
    @PATCH
    suspend fun patch(
        @Url url: String,
        @Header("Authorization") auth: String,
        @Body document: FireDocument,
    ): FireDocument
}
