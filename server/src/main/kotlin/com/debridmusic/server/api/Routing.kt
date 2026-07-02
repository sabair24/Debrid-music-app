package com.debridmusic.server.api

import com.debridmusic.server.ServerConfig
import com.debridmusic.server.ServerSettings
import com.debridmusic.server.cast.CastManager
import com.debridmusic.server.index.IndexStore
import com.debridmusic.server.model.CastControlRequest
import com.debridmusic.server.model.CastDeviceDto
import com.debridmusic.server.model.CastPlayRequest
import com.debridmusic.server.model.CatalogDto
import com.debridmusic.server.model.HealthDto
import com.debridmusic.server.model.IngestMetadata
import com.debridmusic.server.model.TokenRequest
import com.debridmusic.server.model.TokenResponse
import com.debridmusic.server.service.ArtworkService
import com.debridmusic.server.service.IngestService
import com.debridmusic.server.torbox.OnlineDownloadRequest
import com.debridmusic.server.torbox.OnlineService
import com.debridmusic.server.torbox.ResolvedDto
import com.debridmusic.server.search.SearchResult
import io.ktor.http.*
import io.ktor.http.content.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.plugins.autohead.*
import io.ktor.server.plugins.callloging.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.plugins.cors.routing.*
import io.ktor.server.plugins.partialcontent.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.json.Json
import java.io.File

fun Application.configureServer(
    config: ServerConfig,
    store: IndexStore,
    artwork: ArtworkService,
    ingest: IngestService,
    castManager: CastManager,
    settings: ServerSettings,
    online: OnlineService,
) {
    val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    // The single-page web UI (bundled in resources). Served without auth; the page
    // itself picks up the access token from the ?token= query the desktop app opens with.
    val webUi = object {}.javaClass.classLoader.getResource("webui/index.html")?.readText()

    install(ContentNegotiation) { json(json) }
    install(PartialContent)      // HTTP Range support for /stream
    install(AutoHeadResponse)
    install(CallLogging)
    install(CORS) {
        anyHost()
        allowHeader(HttpHeaders.Authorization)
        allowHeader(HttpHeaders.ContentType)
        HttpMethod.DefaultMethods.forEach { allowMethod(it) }
    }

    fun ApplicationCall.authorized(): Boolean {
        val header = request.header(HttpHeaders.Authorization).orEmpty()
        val bearer = header.removePrefix("Bearer ").trim()
        val query = request.queryParameters["token"].orEmpty()
        return bearer == config.authToken || query == config.authToken
    }

    routing {
        // Web UI (PC "main app" — also reachable from iPad/Shield browsers on the LAN).
        get("/") {
            if (webUi != null) call.respondText(webUi, ContentType.Text.Html)
            else call.respondText("DebridMusic server is running.", ContentType.Text.Plain)
        }

        get("/health") {
            call.respond(HealthDto(version = ServerConfig.VERSION))
        }

        post("/auth/token") {
            val req = runCatching { call.receive<TokenRequest>() }.getOrDefault(TokenRequest())
            val ok = (req.username == config.username && req.password == config.password) ||
                req.password == config.authToken
            if (ok) call.respond(TokenResponse(config.authToken))
            else call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "invalid credentials"))
        }

        // ── Protected ────────────────────────────────────────────────────────
        route("/api") {
            intercept(ApplicationCallPipeline.Plugins) {
                if (!call.authorized()) {
                    call.respond(HttpStatusCode.Unauthorized); finish()
                }
            }
            get("/library/artists") { call.respond(store.artists()) }
            get("/library/albums") { call.respond(store.albums()) }
            get("/library/tracks") {
                val albumId = call.request.queryParameters["albumId"]
                val artistId = call.request.queryParameters["artistId"]
                call.respond(store.tracks(albumId, artistId))
            }
            get("/catalog") {
                call.respond(
                    CatalogDto(
                        artists = store.artists(), albums = store.albums(), tracks = store.tracks(),
                        generatedAt = System.currentTimeMillis(),
                    )
                )
            }
            get("/search") {
                val q = call.request.queryParameters["q"].orEmpty()
                call.respond(if (q.isBlank()) com.debridmusic.server.model.SearchResultDto() else store.search(q))
            }

            // ── Casting to Sonos / DLNA renderers ────────────────────────────
            get("/cast/devices") {
                val devices = runCatching { castManager.devices() }.getOrDefault(emptyList())
                call.respond(devices.map { CastDeviceDto(it.id, it.name, it.host) })
            }
            post("/cast/play") {
                val req = call.receive<CastPlayRequest>()
                val queue = if (req.queue.isNotEmpty()) req.queue else listOfNotNull(req.trackId)
                runCatching { castManager.play(req.device, queue, req.index) }
                    .onSuccess { call.respond(mapOf("ok" to true)) }
                    .onFailure { call.respond(HttpStatusCode.BadGateway, mapOf("error" to (it.message ?: "cast failed"))) }
            }
            post("/cast/control") {
                val req = call.receive<CastControlRequest>()
                runCatching { castManager.control(req.device, req.action, req.value) }
                    .onSuccess { call.respond(mapOf("ok" to true)) }
                    .onFailure { call.respond(HttpStatusCode.BadGateway, mapOf("error" to (it.message ?: "control failed"))) }
            }

            // ── Online: search / stream / download via TorBox ────────────────
            get("/online/search") {
                val q = call.request.queryParameters["q"].orEmpty()
                if (q.isBlank()) { call.respond(emptyList<SearchResult>()); return@get }
                runCatching { online.search(q) }
                    .onSuccess { call.respond(it) }
                    .onFailure { call.respond(HttpStatusCode.BadGateway, mapOf("error" to (it.message ?: "search failed"))) }
            }
            get("/online/status") {
                call.respond(mapOf("torboxReady" to online.torBoxReady()))
            }
            post("/online/resolve") {
                val result = call.receive<SearchResult>()
                runCatching { online.resolveStreamUrl(result) }
                    .onSuccess { call.respond(ResolvedDto(it, result.name)) }
                    .onFailure { call.respond(HttpStatusCode.BadGateway, mapOf("error" to (it.message ?: "resolve failed"))) }
            }
            post("/online/tracklist") {
                val result = call.receive<SearchResult>()
                runCatching { online.tracklist(result) }
                    .onSuccess { call.respond(it) }
                    .onFailure { call.respond(HttpStatusCode.BadGateway, mapOf("error" to (it.message ?: "tracklist failed"))) }
            }
            get("/online/resolveTrack") {
                val torrentId = call.request.queryParameters["torrentId"]?.toLongOrNull()
                val fileId = call.request.queryParameters["fileId"]?.toLongOrNull()
                if (torrentId == null || fileId == null) { call.respond(HttpStatusCode.BadRequest); return@get }
                runCatching { online.resolveTrackUrl(torrentId, fileId) }
                    .onSuccess { call.respond(ResolvedDto(it, "")) }
                    .onFailure { call.respond(HttpStatusCode.BadGateway, mapOf("error" to (it.message ?: "resolve failed"))) }
            }
            post("/online/download") {
                val req = call.receive<OnlineDownloadRequest>()
                runCatching { online.enqueueDownload(req.result, req.fileId) }
                    .onSuccess { call.respond(mapOf("queued" to it)) }
                    .onFailure { call.respond(HttpStatusCode.BadGateway, mapOf("error" to (it.message ?: "download failed"))) }
            }
            get("/online/jobs") { call.respond(online.jobs()) }

            // ── Server settings (API keys / logins) ──────────────────────────
            // GET returns only which keys are set (never the secret values).
            get("/settings") { call.respond(settings.presence()) }
            post("/settings") {
                val updates = runCatching { call.receive<Map<String, String>>() }.getOrDefault(emptyMap())
                settings.set(updates)
                call.respond(settings.presence())
            }
            post("/ingest") {
                val multipart = call.receiveMultipart()
                var meta = IngestMetadata()
                var fileName = "track.mp3"
                var response: com.debridmusic.server.model.IngestResponse? = null
                multipart.forEachPart { part ->
                    when (part) {
                        is PartData.FormItem -> if (part.name == "metadata") {
                            meta = runCatching { json.decodeFromString<IngestMetadata>(part.value) }.getOrDefault(meta)
                        }
                        is PartData.FileItem -> {
                            fileName = part.originalFileName ?: fileName
                            response = part.streamProvider().use { ingest.ingest(fileName, it, meta) }
                        }
                        else -> {}
                    }
                    part.dispose()
                }
                if (response != null) call.respond(response!!)
                else call.respond(HttpStatusCode.BadRequest, mapOf("error" to "no file part"))
            }
        }

        get("/stream/{id}") {
            if (!call.authorized()) { call.respond(HttpStatusCode.Unauthorized); return@get }
            val track = call.parameters["id"]?.let { store.track(it) }
            val file = track?.let { File(config.musicRoots.getOrNull(it.rootIndex), it.relPath) }
            if (file == null || !file.isFile) { call.respond(HttpStatusCode.NotFound); return@get }
            track.mime?.let { call.response.header(HttpHeaders.ContentType, it) }
            call.respondFile(file)
        }

        get("/art/{ref}") {
            if (!call.authorized()) { call.respond(HttpStatusCode.Unauthorized); return@get }
            val art = call.parameters["ref"]?.let { artwork.forAlbum(it) }
            if (art == null) { call.respond(HttpStatusCode.NotFound); return@get }
            call.respondBytes(art.bytes, ContentType.parse(art.contentType))
        }
    }
}
