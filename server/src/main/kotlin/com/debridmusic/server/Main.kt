package com.debridmusic.server

import com.debridmusic.server.api.configureServer
import com.debridmusic.server.cast.CastManager
import com.debridmusic.server.cast.UpnpCast
import com.debridmusic.server.index.IndexStore
import com.debridmusic.server.scan.FileWatcher
import com.debridmusic.server.scan.LibraryScanner
import com.debridmusic.server.search.ApibaySource
import com.debridmusic.server.search.BitSearchSource
import com.debridmusic.server.search.KnabenSource
import com.debridmusic.server.search.RuTrackerSource
import com.debridmusic.server.search.SearchAggregator
import com.debridmusic.server.metadata.EnrichmentService
import com.debridmusic.server.service.ArtworkService
import com.debridmusic.server.service.IngestService
import com.debridmusic.server.torbox.OnlineService
import com.debridmusic.server.torbox.TorBoxClient
import com.debridmusic.server.util.NetworkInfo
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.slf4j.LoggerFactory

fun main(args: Array<String>) = runHeadlessServer(args)

/** Headless CLI/service startup (blocks). The desktop tray app calls this when there's no display. */
fun runHeadlessServer(args: Array<String>) {
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
    val artwork = ArtworkService(config.musicRoots, store, java.io.File(config.dataDir, "artcache"))
    val ingest = IngestService(config.musicRoots, scanner, store)
    val cast = CastManager(store, UpnpCast(), lanBaseUrlFor = { host -> NetworkInfo.lanBaseUrlFor(host, config.port) }, token = config.authToken)
    val settings = ServerSettings(java.io.File(config.dataDir, "settings.properties"))
    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    val aggregator = SearchAggregator(listOf(ApibaySource(), BitSearchSource(), KnabenSource(), RuTrackerSource(settings)))
    val torBoxClient = TorBoxClient { settings.get(ServerSettings.TORBOX_API_KEY) }
    val online = OnlineService(settings, aggregator, torBoxClient, config.musicRoots.first(), onLibraryChanged = { scanner.scan() }, appScope)
    val enrichment = EnrichmentService(store, artwork, java.io.File(config.dataDir, "artcache"), appScope)
    val soulseek = com.debridmusic.server.soulseek.SoulseekService(settings, com.debridmusic.server.soulseek.SoulseekClient(), config.musicRoots.first(), onLibraryChanged = { scanner.scan() }, appScope)

    log.info("Music roots: {}", config.musicRoots.joinToString { it.absolutePath })
    log.info("Indexing…")
    scanner.scan()
    log.info("Indexed {} tracks", store.trackCount())
    enrichment.enrichInBackground()

    FileWatcher(config.musicRoots, onChange = { scanner.scan() }).start()

    log.info("Auth token: {}", config.authToken)
    log.info("Open the app in a browser: {}?token={}", NetworkInfo.lanBaseUrl(config.port), config.authToken)
    log.info("Listening on http://{}:{}", config.bindAddress, config.port)

    embeddedServer(Netty, port = config.port, host = config.bindAddress) {
        configureServer(config, store, artwork, ingest, cast, settings, online, enrichment, soulseek)
    }.start(wait = true)
}
