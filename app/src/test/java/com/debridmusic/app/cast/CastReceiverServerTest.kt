package com.debridmusic.app.cast

import com.google.gson.Gson
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * The wire contract the Mac and the iPad talk to.
 *
 * Everything here connects over **IPv4** on purpose. `ServerSocket(port)` binds the wildcard
 * address, which on Android resolves to IPv6 only — the listener then looks perfectly healthy
 * while every IPv4 connection in the house is refused, with nothing in the log to say why. The
 * media app lost a day to exactly that, so it is pinned down here rather than left to a comment.
 */
class CastReceiverServerTest {

    private lateinit var server: CastReceiverServer
    private val received = mutableListOf<CastRequest>()
    private var stops = 0

    @Before
    fun setUp() {
        received.clear()
        stops = 0
        server = CastReceiverServer(
            onPlay = { synchronized(received) { received += it } },
            onStop = { stops++ },
        )
        server.start()
        waitForListening()
    }

    @After
    fun tearDown() {
        server.stop()
    }

    @Test
    fun `answers a ping over IPv4`() {
        val response = request("GET /ping HTTP/1.1\r\nHost: x\r\n\r\n")
        assertTrue("expected a 200, got:\n$response", response.startsWith("HTTP/1.1 200"))
        assertTrue(response.contains("\"ready\":true"))
    }

    @Test
    fun `a play request reaches the player, with the whole queue`() {
        val body = Gson().toJson(
            CastRequest(
                streamUrls = listOf(
                    "http://192.168.0.10:47820/stream/a.flac?token=t",
                    "http://192.168.0.10:47820/stream/b.flac?token=t",
                ),
                index = 1,
                startMs = 42_000,
                title = "Sour Times",
                artist = "Portishead",
                album = "Dummy",
            )
        )
        val response = post("/play", body)
        assertTrue(response.startsWith("HTTP/1.1 200"))

        val request = awaitRequest()
        assertNotNull(request)
        // The whole queue, not just the first track: sending an album has to play the album.
        assertEquals(2, request!!.streamUrls.size)
        assertEquals(1, request.index)
        assertEquals(42_000L, request.startMs)
        assertEquals("Portishead", request.artist)
    }

    @Test
    fun `the sender is answered before playback starts`() {
        // Starting playback pulls the first bytes over the network. A sender that has to wait for
        // that reads the delay as "the Shield is not responding" when it is doing what was asked.
        val start = System.currentTimeMillis()
        post("/play", Gson().toJson(CastRequest(streamUrls = listOf("http://x/a.flac"))))
        val elapsed = System.currentTimeMillis() - start
        assertTrue("answering took ${elapsed}ms", elapsed < 1000)
    }

    @Test
    fun `an empty request is refused rather than played`() {
        val response = post("/play", """{"streamUrls":[]}""")
        assertTrue(response.startsWith("HTTP/1.1 400"))
        assertEquals(0, synchronized(received) { received.size })
    }

    @Test
    fun `malformed json does not take the listener down`() {
        val response = post("/play", "{ this is not json")
        assertTrue(response.startsWith("HTTP/1.1 400"))
        // And the next real request still works — one bad sender must not end the session.
        assertTrue(request("GET /ping HTTP/1.1\r\n\r\n").startsWith("HTTP/1.1 200"))
    }

    @Test
    fun `an unknown path is a 404`() {
        assertTrue(request("GET /nope HTTP/1.1\r\n\r\n").startsWith("HTTP/1.1 404"))
    }

    @Test
    fun `stop is passed on`() {
        assertTrue(post("/stop", "").startsWith("HTTP/1.1 200"))
        assertEquals(1, stops)
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    /** Connects to 127.0.0.1 explicitly — an IPv6-only bind fails here and nowhere else. */
    private fun request(raw: String): String =
        Socket().use { socket ->
            socket.connect(
                InetSocketAddress(Inet4Address.getByName("127.0.0.1"), CastReceiverServer.PORT),
                2000,
            )
            socket.soTimeout = 3000
            socket.getOutputStream().write(raw.toByteArray())
            socket.getOutputStream().flush()
            BufferedReader(InputStreamReader(socket.getInputStream())).readText()
        }

    private fun post(path: String, body: String): String = request(
        "POST $path HTTP/1.1\r\nHost: x\r\nContent-Length: ${body.toByteArray().size}\r\n" +
            "Content-Type: application/json\r\n\r\n$body"
    )

    private fun waitForListening() {
        val deadline = System.currentTimeMillis() + 5000
        while (System.currentTimeMillis() < deadline) {
            try {
                Socket().use {
                    it.connect(
                        InetSocketAddress(Inet4Address.getByName("127.0.0.1"), CastReceiverServer.PORT),
                        200,
                    )
                }
                return
            } catch (_: Exception) {
                Thread.sleep(50)
            }
        }
        throw AssertionError("the receiver never came up on IPv4 127.0.0.1:${CastReceiverServer.PORT}")
    }

    private fun awaitRequest(): CastRequest? {
        val latch = CountDownLatch(1)
        val deadline = System.currentTimeMillis() + 3000
        while (System.currentTimeMillis() < deadline) {
            synchronized(received) { if (received.isNotEmpty()) return received.first() }
            latch.await(50, TimeUnit.MILLISECONDS)
        }
        return null
    }
}
