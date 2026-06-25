package com.debridmusic.server.scan

import org.slf4j.LoggerFactory
import java.io.File
import java.nio.file.FileSystems
import java.nio.file.Path
import java.nio.file.StandardWatchEventKinds.ENTRY_CREATE
import java.nio.file.StandardWatchEventKinds.ENTRY_DELETE
import java.nio.file.StandardWatchEventKinds.ENTRY_MODIFY
import java.nio.file.WatchKey
import java.nio.file.WatchService
import kotlin.concurrent.thread
import kotlin.io.path.isDirectory

/**
 * Watches the music roots (recursively) and triggers a debounced rescan when files
 * change, so pushed/ingested files appear without a manual refresh.
 */
class FileWatcher(
    private val roots: List<File>,
    private val onChange: () -> Unit,
    private val debounceMs: Long = 2_000,
) {
    private val log = LoggerFactory.getLogger(FileWatcher::class.java)
    private val watch: WatchService = FileSystems.getDefault().newWatchService()
    private val keys = HashMap<WatchKey, Path>()

    @Volatile private var lastEvent = 0L
    @Volatile private var running = false

    fun start() {
        roots.filter { it.isDirectory }.forEach { registerRecursive(it.toPath()) }
        running = true
        thread(name = "music-file-watcher", isDaemon = true) { watchLoop() }
        thread(name = "music-rescan-debounce", isDaemon = true) { debounceLoop() }
        log.info("Watching {} root(s) for changes", roots.size)
    }

    private fun registerRecursive(dir: Path) {
        runCatching {
            keys[dir.register(watch, ENTRY_CREATE, ENTRY_DELETE, ENTRY_MODIFY)] = dir
            dir.toFile().listFiles()?.filter { it.isDirectory }?.forEach { registerRecursive(it.toPath()) }
        }
    }

    private fun watchLoop() {
        while (running) {
            val key = runCatching { watch.take() }.getOrNull() ?: break
            val base = keys[key]
            for (event in key.pollEvents()) {
                lastEvent = System.currentTimeMillis()
                // Register newly created subdirectories so they're watched too.
                if (event.kind() == ENTRY_CREATE && base != null) {
                    val child = base.resolve(event.context() as Path)
                    if (runCatching { child.isDirectory() }.getOrDefault(false)) registerRecursive(child)
                }
            }
            if (!key.reset()) keys.remove(key)
        }
    }

    private fun debounceLoop() {
        while (running) {
            Thread.sleep(500)
            val ts = lastEvent
            if (ts != 0L && System.currentTimeMillis() - ts >= debounceMs) {
                lastEvent = 0L
                runCatching { onChange() }.onFailure { log.warn("Rescan failed: {}", it.message) }
            }
        }
    }

    fun stop() { running = false; runCatching { watch.close() } }
}
