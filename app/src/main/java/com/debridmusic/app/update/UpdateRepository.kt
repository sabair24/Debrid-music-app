package com.debridmusic.app.update

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import com.debridmusic.app.BuildConfig
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Self-update for sideloaded builds: checks the latest GitHub Release, and if its
 * build number is newer than this build, downloads the APK and hands it to the
 * system package installer.
 *
 * Note: self-updating via APK download is intended for sideloaded distribution.
 * Google Play policy forbids it, so this path is only used for the GitHub build.
 */
@Singleton
class UpdateRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    private val gitHubApi: GitHubApi,
    private val okHttpClient: OkHttpClient,
) {
    data class UpdateInfo(
        val available: Boolean,
        val latestBuild: Int,
        val versionLabel: String,
        val notes: String,
        val apkUrl: String?,
    )

    suspend fun check(): Result<UpdateInfo> = runCatching {
        val (owner, repo) = BuildConfig.GITHUB_REPO.split("/", limit = 2)
        val release = gitHubApi.latestRelease(owner, repo)
        val latestBuild = parseBuildNumber(release.tagName)
        val apk = release.assets.firstOrNull { it.name.endsWith(".apk", ignoreCase = true) }
        UpdateInfo(
            available = latestBuild > BuildConfig.BUILD_NUMBER && apk != null,
            latestBuild = latestBuild,
            versionLabel = release.name ?: release.tagName,
            notes = release.body.orEmpty(),
            apkUrl = apk?.browserDownloadUrl,
        )
    }

    // Tags look like "v1.0.0-build42" — pull out the trailing build number.
    private fun parseBuildNumber(tag: String): Int =
        Regex("build(\\d+)", RegexOption.IGNORE_CASE).find(tag)?.groupValues?.get(1)?.toIntOrNull() ?: 0

    /** Downloads the APK (reporting 0f..1f progress) and launches the installer. */
    suspend fun downloadAndInstall(apkUrl: String, onProgress: (Float) -> Unit) = withContext(Dispatchers.IO) {
        val request = Request.Builder().url(apkUrl).build()
        okHttpClient.newCall(request).execute().use { resp ->
            if (!resp.isSuccessful) error("Download mislukt (HTTP ${resp.code})")
            val body = resp.body ?: error("Lege download")
            val total = body.contentLength()
            val file = File(context.cacheDir, "update.apk")
            body.byteStream().use { input ->
                file.outputStream().use { out ->
                    val buf = ByteArray(64 * 1024)
                    var read = 0L
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        read += n
                        if (total > 0) onProgress((read.toFloat() / total).coerceIn(0f, 1f))
                    }
                }
            }
            onProgress(1f)
            launchInstaller(file)
        }
    }

    private fun launchInstaller(apk: File) {
        val uri: Uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", apk)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }
}
