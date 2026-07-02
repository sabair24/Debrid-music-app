package com.debridmusic.server

import com.debridmusic.server.api.configureServer
import com.debridmusic.server.cast.CastManager
import com.debridmusic.server.cast.UpnpCast
import com.debridmusic.server.index.IndexStore
import com.debridmusic.server.index.ScannedTrack
import com.debridmusic.server.model.HealthDto
import com.debridmusic.server.model.TrackDto
import com.debridmusic.server.service.ArtworkService
import com.debridmusic.server.service.IngestService
import com.debridmusic.server.scan.LibraryScanner
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.server.testing.*
import kotlinx.serialization.json.Json
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ApiTest {
    private val json = Json { ignoreUnknownKeys = true }

    private fun testConfig(): Pair<ServerConfig, IndexStore> {
        val dir = File.createTempFile("srvtest", "").apply { delete(); mkdirs() }
        val music = File(dir, "music").apply { mkdirs() }
        val config = ServerConfig(
            musicRoots = listOf(music), bindAddress = "127.0.0.1", port = 0,
            authToken = "secret-token", username = "u", password = "p", dataDir = dir,
        )
        val store = IndexStore(config.indexFile)
        // Seed one track directly (no audio file needed for API-shape tests).
        store.replaceAll(
            listOf(
                ScannedTrack(
                    id = "t1", albumId = "al1", artistId = "ar1", title = "Song",
                    artistName = "Artist", albumTitle = "Album", trackNo = 1, discNo = 1,
                    durationMs = 1000, bitrate = 320, sampleRate = 44100, lossless = false,
                    sizeBytes = 100, year = 2020, genre = "Pop", mime = "audio/mpeg",
                    rootIndex = 0, relPath = "Artist/Album/song.mp3",
                )
            ),
            generatedAt = 0L,
        )
        return config to store
    }

    private fun ApplicationTestBuilder.setup(config: ServerConfig, store: IndexStore) {
        val scanner = LibraryScanner(config.musicRoots, store)
        val cast = CastManager(store, UpnpCast(), lanBaseUrlFor = { "http://127.0.0.1:${config.port}" }, token = config.authToken)
        application {
            configureServer(config, store, ArtworkService(config.musicRoots, store), IngestService(config.musicRoots, scanner, store), cast)
        }
    }

    @Test
    fun health_is_public() = testApplication {
        val (config, store) = testConfig()
        setup(config, store)
        val resp = client.get("/health")
        assertEquals(HttpStatusCode.OK, resp.status)
        val health = json.decodeFromString<HealthDto>(resp.bodyAsText())
        assertEquals("ok", health.status)
    }

    @Test
    fun library_requires_auth() = testApplication {
        val (config, store) = testConfig()
        setup(config, store)
        assertEquals(HttpStatusCode.Unauthorized, client.get("/api/library/tracks").status)
    }

    @Test
    fun library_returns_tracks_with_token() = testApplication {
        val (config, store) = testConfig()
        setup(config, store)
        val resp = client.get("/api/library/tracks") {
            header(HttpHeaders.Authorization, "Bearer secret-token")
        }
        assertEquals(HttpStatusCode.OK, resp.status)
        val tracks = json.decodeFromString<List<TrackDto>>(resp.bodyAsText())
        assertEquals(1, tracks.size)
        assertEquals("Song", tracks[0].title)
        assertTrue(tracks[0].streamPath.endsWith("/stream/t1"))
    }
}
