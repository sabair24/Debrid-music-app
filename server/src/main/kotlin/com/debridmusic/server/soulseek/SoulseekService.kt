package com.debridmusic.server.soulseek

import com.debridmusic.server.ServerSettings
import com.debridmusic.server.torbox.DownloadJobDto
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.slf4j.LoggerFactory
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicLong

/** Server-side Soulseek: search + background download into the music library. */
class SoulseekService(
    private val settings: ServerSettings,
    private val client: SoulseekClient,
    private val musicRoot: File,
    private val onLibraryChanged: () -> Unit,
    private val appScope: CoroutineScope,
) {
    private val log = LoggerFactory.getLogger(SoulseekService::class.java)
    private val ids = AtomicLong(1)
    private val jobs = CopyOnWriteArrayList<Job>()

    private class Job(val id: Long, val name: String, val user: String) {
        @Volatile var status = "downloading"
        @Volatile var progress = 0f
    }

    fun available(): Boolean =
        settings.get(ServerSettings.SOULSEEK_USER) != null && settings.get(ServerSettings.SOULSEEK_PASS) != null

    private fun creds(): Pair<String, String> {
        val u = settings.get(ServerSettings.SOULSEEK_USER) ?: error("Stel je Soulseek-login in (Instellingen).")
        val p = settings.get(ServerSettings.SOULSEEK_PASS) ?: error("Stel je Soulseek-login in (Instellingen).")
        return u to p
    }

    suspend fun search(query: String): List<SoulseekFile> {
        val (u, p) = creds()
        return client.search(u, p, query)
    }

    fun jobs(): List<DownloadJobDto> = jobs.map { DownloadJobDto(it.id, it.name, it.user, it.status, it.progress) }

    /** Queue a file for download into the library; false if no credentials are set. */
    fun enqueue(file: SoulseekFile): Boolean {
        if (!available()) return false
        val (u, p) = creds()
        val meta = SoulseekPath.parse(file.filename)
        val ext = file.extension.ifEmpty { "mp3" }
        val artist = sanitize(meta.artist.ifEmpty { file.username })
        val title = sanitize(meta.title.ifEmpty { file.displayName.substringBeforeLast('.', file.displayName) })
        val dest = File(musicRoot, "DebridMusic Downloads/Soulseek/$artist/$title.$ext")
        val job = Job(ids.getAndIncrement(), file.displayName, file.username)
        jobs.add(0, job)
        appScope.launch {
            when (val res = client.download(u, p, file, dest) { rec, tot -> if (tot > 0) job.progress = (rec.toFloat() / tot).coerceIn(0f, 1f) }) {
                is SlskResult.Done -> { job.progress = 1f; job.status = "done"; log.info("Soulseek downloaded {}", res.path); onLibraryChanged() }
                is SlskResult.Fail -> { job.status = "failed"; log.warn("Soulseek download failed: {}", res.reason) }
            }
        }
        return true
    }

    private fun sanitize(s: String) = s.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim().ifEmpty { "unknown" }
}
