package com.debridmusic.server.service

import com.debridmusic.server.index.IndexStore
import com.debridmusic.server.model.IngestMetadata
import com.debridmusic.server.model.IngestResponse
import com.debridmusic.server.scan.LibraryScanner
import com.debridmusic.server.util.Ids
import org.slf4j.LoggerFactory
import java.io.File
import java.io.InputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * Accepts an uploaded audio file from a client and writes it into the first music root
 * under <Artist>/<Album>/<file>, then re-scans so it appears in the library.
 */
class IngestService(
    private val roots: List<File>,
    private val scanner: LibraryScanner,
    private val store: IndexStore,
) {
    private val log = LoggerFactory.getLogger(IngestService::class.java)
    private val root: File get() = roots.first()

    fun ingest(fileName: String, source: InputStream, meta: IngestMetadata): IngestResponse {
        val artistDir = sanitize(meta.artist.ifBlank { "Unknown Artist" })
        val albumDir = sanitize(meta.album.ifBlank { "Unknown Album" })
        val safeName = sanitize(fileName.ifBlank { "track.mp3" })

        val targetDir = File(root, "$artistDir/$albumDir").apply { mkdirs() }
        val target = uniqueFile(targetDir, safeName)

        // Atomic-ish write: stream to a temp file in the same dir, then move into place.
        val tmp = File.createTempFile("ingest", ".part", targetDir)
        try {
            tmp.outputStream().use { out -> source.copyTo(out, bufferSize = 256 * 1024) }
            Files.move(tmp.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE)
        } catch (e: Exception) {
            tmp.delete(); throw e
        }

        // Re-scan so the watcher-independent path also indexes immediately.
        scanner.scan()

        val relPath = root.toPath().relativize(target.toPath()).toString().replace(File.separatorChar, '/')
        val trackId = Ids.track(0, relPath)
        log.info("Ingested {} -> {}", fileName, relPath)
        return IngestResponse(trackId = trackId, streamPath = "/stream/$trackId")
    }

    private fun uniqueFile(dir: File, name: String): File {
        var candidate = File(dir, name)
        if (!candidate.exists()) return candidate
        val stem = name.substringBeforeLast('.', name)
        val ext = name.substringAfterLast('.', "")
        var i = 1
        while (candidate.exists()) {
            candidate = File(dir, if (ext.isEmpty()) "$stem ($i)" else "$stem ($i).$ext")
            i++
        }
        return candidate
    }

    private fun sanitize(s: String): String =
        s.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim().take(180).ifBlank { "_" }
}
