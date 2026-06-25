package com.debridmusic.server.api

import com.debridmusic.server.ServerConfig
import com.debridmusic.server.index.IndexStore
import com.debridmusic.server.model.CatalogDto
import com.debridmusic.server.model.HealthDto
import com.debridmusic.server.model.IngestMetadata
import com.debridmusic.server.model.TokenRequest
import com.debridmusic.server.model.TokenResponse
import com.debridmusic.server.service.ArtworkService
import com.debridmusic.server.service.IngestService
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
) {
    val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

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
