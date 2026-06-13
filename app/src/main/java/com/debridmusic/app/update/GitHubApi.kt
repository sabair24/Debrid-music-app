package com.debridmusic.app.update

import com.google.gson.annotations.SerializedName
import retrofit2.http.GET
import retrofit2.http.Path

interface GitHubApi {
    @GET("repos/{owner}/{repo}/releases/latest")
    suspend fun latestRelease(
        @Path("owner") owner: String,
        @Path("repo") repo: String,
    ): GitHubRelease
}

data class GitHubRelease(
    @SerializedName("tag_name") val tagName: String,
    val name: String?,
    val body: String?,
    val assets: List<GitHubAsset> = emptyList(),
)

data class GitHubAsset(
    val name: String,
    val size: Long = 0,
    @SerializedName("browser_download_url") val browserDownloadUrl: String,
)
