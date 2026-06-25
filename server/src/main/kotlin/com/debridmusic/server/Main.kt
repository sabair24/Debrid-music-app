package com.debridmusic.server

import com.debridmusic.server.api.configureServer
import com.debridmusic.server.index.IndexStore
import com.debridmusic.server.scan.FileWatcher
import com.debridmusic.server.scan.LibraryScanner
import com.debridmusic.server.service.ArtworkService
import com.debridmusic.server.service.IngestService
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import org.slf4j.LoggerFactory

fun main(args: Array<String>) {
    val log = LoggerFactory.getLogger("DebridMusicServer")
    val config = runCatching { ServerConfig.load(args) }.getOrElse {
        System.err.println("Configuration error: ${it.message}")
        System.err.println(
            """
            |Usage: java -jar musicserver.jar [config.properties]
            |Required: MUSIC_ROOTS=/path/to/music (comma-separated for multiple)
            |Optional: PORT (4533), BIND (0.0.0.0), AUTH_TOKEN (auto-generated), DATA_DIR (./data),
            |          USERNAME (music), PASSWORD (= token)
            """.trimMargin()
        )
        return
    }

    val store = IndexStore(config.indexFile)
    val scanner = LibraryScanner(config.musicRoots, store)
    val artwork = ArtworkService(config.musicRoots, store)
    val ingest = IngestService(config.musicRoots, scanner, store)

    log.info("Music roots: {}", config.musicRoots.joinToString { it.absolutePath })
    log.info("Indexing…")
    scanner.scan()
    log.info("Indexed {} tracks", store.trackCount())

    FileWatcher(config.musicRoots, onChange = { scanner.scan() }).start()

    log.info("Auth token: {}", config.authToken)
    log.info("Listening on http://{}:{}", config.bindAddress, config.port)

    embeddedServer(Netty, port = config.port, host = config.bindAddress) {
        configureServer(config, store, artwork, ingest)
    }.start(wait = true)
}
