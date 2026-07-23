package com.debridmusic.app.cast

import android.util.Log
import com.google.gson.Gson
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** What a sender asks this device to play. */
data class CastRequest(
    val trackIds: List<String> = emptyList(),
    val streamUrls: List<String> = emptyList(),
    val index: Int = 0,
    val startMs: Long = 0,
    val title: String = "",
    val artist: String = "",
    val album: String = "",
    val artUrl: String? = null,
)

/**
 * Lets the Mac and the iPad hand playback to this device.
 *
 * A tiny HTTP listener rather than Google Cast: Cast Connect needs a registered receiver app in
 * the Google Cast Console, and the Default Media Receiver would decode the audio itself. This
 * route hands the URL straight to ExoPlayer, which plays FLAC bit-perfect out of the Shield's
 * HDMI — the entire point of sending it here rather than to a speaker.
 *
 *   GET  /ping   → {"app":"debridmusic","ready":true}
 *   POST /play   → CastRequest, answered once playback has been asked for
 *   POST /stop
 *
 * No auth. It only ever accepts a play command from something already on your home network, and
 * the worst it can do is start a song.
 */
class CastReceiverServer(
    private val onPlay: (CastRequest) -> Unit,
    private val onStop: () -> Unit,
) {
    private val running = AtomicBoolean(false)
    private var socket: ServerSocket? = null
    private val executor = Executors.newCachedThreadPool()
    private val gson = Gson()

    fun start() {
        if (!running.compareAndSet(false, true)) return
        executor.execute {
            try {
                // Bind 0.0.0.0 EXPLICITLY. `ServerSocket(port)` binds the wildcard address, which
                // on Android resolves to IPv6 only — every IPv4 connection from the Mac or the
                // iPad is then refused, silently, with nothing in the log to explain it. This
                // exact mistake cost a day in the media app; do not "simplify" it back.
                val server = ServerSocket()
                server.reuseAddress = true
                server.bind(InetSocketAddress("0.0.0.0", PORT))
                socket = server
                Log.i(TAG, "Cast receiver listening on 0.0.0.0:$PORT")
                while (running.get()) {
                    val client = try {
                        server.accept()
                    } catch (e: Exception) {
                        if (running.get()) Log.w(TAG, "accept failed: ${e.message}")
                        break
                    }
                    executor.execute { handle(client) }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Cast receiver could not start: ${e.message}")
                running.set(false)
            }
        }
    }

    fun stop() {
        running.set(false)
        runCatching { socket?.close() }
        socket = null
    }

    private fun handle(client: Socket) {
        client.use { sock ->
            try {
                sock.soTimeout = 5000
                val reader = BufferedReader(InputStreamReader(sock.getInputStream()))
                val requestLine = reader.readLine() ?: return
                val parts = requestLine.split(" ")
                if (parts.size < 2) return
                val method = parts[0]
                val path = parts[1].substringBefore('?')

                var contentLength = 0
                while (true) {
                    val line = reader.readLine() ?: break
                    if (line.isEmpty()) break
                    if (line.startsWith("Content-Length:", ignoreCase = true)) {
                        contentLength = line.substringAfter(':').trim().toIntOrNull() ?: 0
                    }
                }

                when {
                    path == "/ping" -> respond(sock.getOutputStream(), """{"app":"debridmusic","ready":true}""")

                    path == "/play" && method == "POST" -> {
                        val body = readBody(reader, contentLength)
                        val request = runCatching { gson.fromJson(body, CastRequest::class.java) }.getOrNull()
                        if (request == null || (request.streamUrls.isEmpty() && request.trackIds.isEmpty())) {
                            respond(sock.getOutputStream(), """{"error":"empty request"}""", status = "400 Bad Request")
                        } else {
                            // Answer BEFORE playing. Starting playback pulls the first bytes over
                            // the network, and a sender waiting on that reads as "the Shield is
                            // not responding" when it is simply busy doing what was asked.
                            respond(sock.getOutputStream(), """{"ok":true}""")
                            onPlay(request)
                        }
                    }

                    path == "/stop" && method == "POST" -> {
                        respond(sock.getOutputStream(), """{"ok":true}""")
                        onStop()
                    }

                    else -> respond(sock.getOutputStream(), """{"error":"not found"}""", status = "404 Not Found")
                }
            } catch (e: Exception) {
                Log.w(TAG, "cast request failed: ${e.message}")
            }
        }
    }

    private fun readBody(reader: BufferedReader, length: Int): String {
        if (length <= 0) return ""
        val buffer = CharArray(length)
        var read = 0
        while (read < length) {
            val n = reader.read(buffer, read, length - read)
            if (n < 0) break
            read += n
        }
        return String(buffer, 0, read)
    }

    private fun respond(out: OutputStream, body: String, status: String = "200 OK") {
        val bytes = body.toByteArray()
        val header = buildString {
            append("HTTP/1.1 $status\r\n")
            append("Content-Type: application/json; charset=utf-8\r\n")
            append("Content-Length: ${bytes.size}\r\n")
            append("Access-Control-Allow-Origin: *\r\n")
            append("Connection: close\r\n\r\n")
        }
        out.write(header.toByteArray())
        out.write(bytes)
        out.flush()
    }

    companion object {
        private const val TAG = "CastReceiver"

        /**
         * 8124, not 8123. The Debrid **Media** app already listens on 8123 on the same Shield,
         * and the second binder loses silently — the listener simply never comes up, and a cast
         * from the Mac reads as "the TV ignored me". Verified on the device: 8123 answers
         * `{"app":"debrid-media"}`.
         */
        const val PORT = 8124
    }
}
