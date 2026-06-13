package com.debridmusic.app.soulseek

import android.content.Context
import com.debridmusic.app.soulseek.proto.*
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.random.Random

data class SoulseekFile(
    val username: String,
    val filename: String,
    val size: Long,
    val speed: Int,
    val queueLength: Int,
    val freeSlots: Boolean,
    val bitrate: Int?,
    val durationSec: Int?,
    val sampleRate: Int?,
    val bitDepth: Int?,
    val isVbr: Boolean,
) {
    val displayName: String get() = filename.replace('\\', '/').substringAfterLast('/')
    val extension: String get() = displayName.substringAfterLast('.').lowercase()
    val isFlac: Boolean get() = extension == "flac"
    val isAudio: Boolean get() = extension in setOf("flac", "mp3", "m4a", "ogg", "opus", "wav", "aac", "alac", "ape")
}

sealed class SlskDownloadState {
    data class Queued(val reason: String) : SlskDownloadState()
    data class Downloading(val bytesReceived: Long, val totalBytes: Long) : SlskDownloadState()
    data class Done(val localPath: String) : SlskDownloadState()
    data class Error(val message: String) : SlskDownloadState()
}

private const val SERVER_HOST = "server.slsknet.org"
private const val SERVER_PORT = 2242

@Singleton
class SoulseekClient @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val ticketGen = AtomicInteger(Random.nextInt(10_000, 999_999))

    // ── Search ────────────────────────────────────────────────────────────────

    suspend fun search(
        username: String,
        password: String,
        query: String,
    ): Result<List<SoulseekFile>> = runCatching {
        withContext(Dispatchers.IO) {
            val results = CopyOnWriteArrayList<SoulseekFile>()
            val ticket = ticketGen.incrementAndGet()
            val server = SlskSocket(SERVER_HOST, SERVER_PORT)
            var ctpCount = 0                              // ConnectToPeer messages received
            val peerConnected = AtomicInteger(0)          // peers we successfully TCP-connected to
            val peerGotMsg   = AtomicInteger(0)           // peers that sent us any message after PierceFirewall
            val peerGotCode9 = AtomicInteger(0)           // peers that sent code-9 (SearchResults)

            val seenCodes = mutableListOf<Int>()  // first 15 codes for diagnostics
            var loopEndReason = "timeout"

            try {
                server.connect()
                loginServer(server, username, password)
                server.send(buildSetWaitPort(0))
                server.send(buildFileSearch(ticket, query))
                // Do NOT set a short socket timeout here — a short timeout that fires
                // mid-message corrupts the stream (readFully reads partial data, next
                // message is misframed). Instead we update the timeout to the remaining
                // deadline before every read, so the socket times out only when the
                // deadline is truly reached.

                val peerJobs = mutableListOf<Job>()
                val deadline = System.currentTimeMillis() + 20_000L

                while (System.currentTimeMillis() < deadline && results.size < 200) {
                    val remaining = deadline - System.currentTimeMillis()
                    if (remaining <= 0) break
                    server.setSoTimeout(remaining.coerceIn(200, 60_000).toInt())

                    val msg = try {
                        server.readMessage()
                    } catch (_: java.net.SocketTimeoutException) {
                        loopEndReason = "timeout"
                        break // clean deadline expiry
                    } catch (e: java.io.EOFException) {
                        loopEndReason = "EOF(server dropped)"
                        break
                    } catch (e: Exception) {
                        loopEndReason = "err:${e.javaClass.simpleName}"
                        break
                    }
                    val buf = ByteBuffer.wrap(msg).order(ByteOrder.LITTLE_ENDIAN)
                    val code = buf.readUInt32().toInt()
                    if (seenCodes.size < 15) seenCodes.add(code)

                    if (code == 18) { // ConnectToPeer
                        ctpCount++
                        runCatching {
                            val peerUser = buf.readSlskString()
                            val type = buf.readSlskString()
                            val ip = buf.readSlskIp()
                            val port = buf.readUInt32().toInt()
                            val token = buf.readUInt32()

                            if (type == "P" && ip != "0.0.0.0" && port > 0 && peerJobs.size < 50) {
                                val job = CoroutineScope(Dispatchers.IO).launch {
                                    collectPeerResults(ip, port, token, ticket, results,
                                        peerConnected, peerGotMsg, peerGotCode9)
                                }
                                peerJobs.add(job)
                            }
                        }
                    }
                }

                // Wait for in-flight peer connections to finish (generous budget)
                withTimeoutOrNull(12_000L) { peerJobs.forEach { it.join() } }
                peerJobs.forEach { it.cancel() }

            } finally {
                server.close()
            }

            val audioResults = results
                .filter { it.isAudio }
                .sortedWith(
                    compareByDescending<SoulseekFile> { if (it.isFlac) 1 else 0 }
                        .thenByDescending { it.freeSlots }
                        .thenByDescending { it.speed }
                        .thenByDescending { it.size }
                )

            // Surface debug counts when results are empty so we can diagnose the stage
            if (audioResults.isEmpty()) {
                val codesStr = if (seenCodes.isEmpty()) "geen" else seenCodes.joinToString(",")
                error("Geen resultaten — " +
                    "ingelogd: ja, " +
                    "einde: $loopEndReason, " +
                    "codes: $codesStr, " +
                    "CTP: $ctpCount, " +
                    "peers: ${peerConnected.get()}, " +
                    "peer_msg: ${peerGotMsg.get()}, " +
                    "code9: ${peerGotCode9.get()}, " +
                    "ruw: ${results.size}")
            }
            audioResults
        }
    }

    // Connects to the Soulseek server and attempts a login. Returns success or a
    // failure with the server's reason. Used by Settings to confirm credentials.
    suspend fun testLogin(username: String, password: String): Result<Unit> = runCatching {
        withContext(Dispatchers.IO) {
            val server = SlskSocket(SERVER_HOST, SERVER_PORT)
            try {
                server.connect()
                loginServer(server, username, password) // throws on failure
            } finally {
                server.close()
            }
        }
    }

    private suspend fun collectPeerResults(
        ip: String,
        port: Int,
        token: Long,
        ticket: Int,
        results: CopyOnWriteArrayList<SoulseekFile>,
        peerConnected: AtomicInteger,
        peerGotMsg: AtomicInteger,
        peerGotCode9: AtomicInteger,
    ) {
        val peer = SlskSocket(ip, port)
        try {
            peer.connect(connectTimeoutMs = 5_000)
            peerConnected.incrementAndGet()
            peer.setSoTimeout(5_000)
            // ConnectToPeer flow: send PierceFirewall (code 0) with the server-relayed
            // token so the peer can match this connection to their pending search result.
            // PeerInit (code 1) is only for connections WE initiate without the server relay.
            peer.send(buildPierceFirewall(token))

            repeat(10) {
                val msg = try { peer.readMessage() } catch (_: Exception) { return }
                peerGotMsg.incrementAndGet()
                val buf = ByteBuffer.wrap(msg).order(ByteOrder.LITTLE_ENDIAN)
                val code = buf.readUInt32().toInt()

                if (code == 9) { // SearchResults
                    peerGotCode9.incrementAndGet()
                    val raw = ByteArray(buf.remaining()).also { buf.get(it) }
                    val data = tryZlibDecompress(raw)
                    parseSearchResults(ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN), ticket, results)
                    return
                }
            }
        } catch (_: Exception) {
        } finally {
            peer.close()
        }
    }

    private fun parseSearchResults(
        buf: ByteBuffer,
        ticket: Int,
        results: CopyOnWriteArrayList<SoulseekFile>,
    ) {
        try {
            val peerUser = buf.readSlskString()
            val resultTicket = buf.readUInt32().toInt()
            if (resultTicket != ticket) return

            val count = buf.readUInt32().toInt().coerceIn(0, 200)
            val files = mutableListOf<SoulseekFile>()

            repeat(count) {
                if (buf.remaining() < 5) return@repeat
                buf.readUInt8() // entry type (1=file)
                val filename = buf.readSlskString()
                val size = buf.readUInt64()
                buf.readSlskString() // legacy extension field
                val numAttr = buf.readUInt32().toInt().coerceIn(0, 10)
                var bitrate: Int? = null; var duration: Int? = null
                var vbr = false; var sampleRate: Int? = null; var bitDepth: Int? = null
                repeat(numAttr) {
                    val t = buf.readUInt32().toInt()
                    val v = buf.readUInt32().toInt()
                    when (t) { 0 -> bitrate = v; 1 -> duration = v; 2 -> vbr = v != 0; 4 -> sampleRate = v; 5 -> bitDepth = v }
                }
                files.add(SoulseekFile(peerUser, filename, size, 0, 0, false, bitrate, duration, sampleRate, bitDepth, vbr))
            }

            val freeSlots = if (buf.hasRemaining()) buf.readBool() else false
            val speed = if (buf.remaining() >= 4) buf.readUInt32().toInt() else 0
            val queueLen = if (buf.remaining() >= 4) buf.readUInt32().toInt() else 0

            files.forEach { f ->
                results.add(f.copy(freeSlots = freeSlots, speed = speed, queueLength = queueLen))
            }
        } catch (_: Exception) {}
    }

    // ── Download ──────────────────────────────────────────────────────────────

    fun download(
        username: String,
        password: String,
        file: SoulseekFile,
    ): Flow<SlskDownloadState> = channelFlow {
        val server = SlskSocket(SERVER_HOST, SERVER_PORT)
        var pConn: SlskSocket? = null
        val fileSize = AtomicLong(0L)
        try {
            server.connect()
            loginServer(server, username, password)
            server.send(buildSetWaitPort(0))

            // Resolve the uploader's address.
            server.send(buildGetPeerAddress(file.username))
            server.setSoTimeout(10_000)
            val addrData = readUntilCode(server, 3)
            val addrBuf = ByteBuffer.wrap(addrData).order(ByteOrder.LITTLE_ENDIAN)
            addrBuf.readSlskString() // peer username
            val peerIp = addrBuf.readSlskIp()
            val peerPort = addrBuf.readUInt32().toInt()
            if (peerIp == "0.0.0.0" || peerPort == 0) {
                error("Deze gebruiker is niet bereikbaar (firewalled). Probeer een ander resultaat.")
            }

            // Open a peer (P) connection and ask for the file. We send both
            // QueueUpload (the polite queue request) and a direct TransferRequest,
            // so cooperative clients start the upload either way.
            val dlToken = ticketGen.incrementAndGet().toLong()
            val peer = SlskSocket(peerIp, peerPort).also { pConn = it }
            peer.connect(connectTimeoutMs = 8_000)
            peer.send(buildPeerInit(username, "P", dlToken))
            peer.send(buildQueueUpload(file.filename))
            peer.send(buildTransferRequest(0, dlToken, file.filename))
            send(SlskDownloadState.Queued("Aangevraagd — wachten op upload-slot…"))

            // The uploader can't reach us (we're firewalled), so the actual bytes
            // arrive on a separate "F" connection that it asks the server to relay
            // via ConnectToPeer. Meanwhile we watch the P connection for the
            // transfer hand-shake. These run concurrently.
            val denyReason = java.util.concurrent.atomic.AtomicReference<String?>(null)

            // P-connection reader: capture file size and accept the upload.
            val pJob = launch(Dispatchers.IO) {
                runCatching {
                    peer.setSoTimeout(60_000)
                    repeat(40) {
                        val msg = peer.readMessage()
                        val buf = ByteBuffer.wrap(msg).order(ByteOrder.LITTLE_ENDIAN)
                        when (buf.readUInt32().toInt()) {
                            41 -> { // TransferResponse to our request
                                buf.readUInt32() // token
                                if (buf.readBool()) fileSize.compareAndSet(0L, buf.readUInt64())
                                else denyReason.set(buf.readSlskString())
                            }
                            40 -> { // peer initiates the upload
                                buf.readUInt32() // direction
                                val tok = buf.readUInt32()
                                buf.readSlskString() // filename
                                if (buf.remaining() >= 8) fileSize.compareAndSet(0L, buf.readUInt64())
                                peer.send(buildTransferResponse(tok, true)) // accept
                            }
                        }
                    }
                }
            }

            // Server loop: wait for the ConnectToPeer "F" relay, then pull the file.
            val deadline = System.currentTimeMillis() + 90_000L
            var delivered = false
            while (System.currentTimeMillis() < deadline && !delivered) {
                val remaining = deadline - System.currentTimeMillis()
                server.setSoTimeout(remaining.coerceIn(500, 60_000).toInt())
                val msg = try {
                    server.readMessage()
                } catch (_: java.net.SocketTimeoutException) {
                    break
                } catch (_: Exception) {
                    break
                }
                val buf = ByteBuffer.wrap(msg).order(ByteOrder.LITTLE_ENDIAN)
                if (buf.readUInt32().toInt() != 18) continue // only ConnectToPeer

                buf.readSlskString() // peer username
                val type = buf.readSlskString()
                val ip = buf.readSlskIp()
                val port = buf.readUInt32().toInt()
                val ctpToken = buf.readUInt32()
                if (type != "F" || ip == "0.0.0.0" || port <= 0) continue

                // This is the file connection. Pierce, read the transfer ticket,
                // send our offset, then stream the bytes.
                val fConn = SlskSocket(ip, port)
                try {
                    fConn.connect(connectTimeoutMs = 8_000)
                    fConn.send(buildPierceFirewall(ctpToken))
                    fConn.setSoTimeout(60_000)
                    val inp = fConn.rawInputStream()
                    readRaw(inp, 4) // transfer ticket (uint32) — we have one DL in flight
                    fConn.sendRaw(ByteArray(8)) // offset = 0

                    val ext = file.extension.ifBlank { "mp3" }
                    val tempFile = File(context.cacheDir, "slsk_${ticketGen.incrementAndGet()}.$ext")
                    var received = 0L
                    var lastEmit = 0L
                    val total = fileSize.get()
                    tempFile.outputStream().use { out ->
                        val data = ByteArray(65_536)
                        while (true) {
                            if (total > 0 && received >= total) break
                            val n = inp.read(data)
                            if (n < 0) break
                            out.write(data, 0, n)
                            received += n
                            if (received - lastEmit >= 262_144L) {
                                send(SlskDownloadState.Downloading(received, total))
                                lastEmit = received
                            }
                        }
                    }
                    fConn.close()

                    if (received > 0 && (total == 0L || received >= total)) {
                        send(SlskDownloadState.Done(tempFile.absolutePath))
                        delivered = true
                    } else {
                        tempFile.delete()
                    }
                } catch (_: Exception) {
                    runCatching { fConn.close() }
                }
            }

            pJob.cancel()
            if (!delivered) {
                val reason = denyReason.get()
                when {
                    reason != null && reason.contains("Queued", ignoreCase = true) ->
                        send(SlskDownloadState.Queued("In wachtrij bij gebruiker — probeer later of een ander resultaat."))
                    reason != null ->
                        send(SlskDownloadState.Error("Geweigerd door uploader: $reason"))
                    else ->
                        send(SlskDownloadState.Error("Geen reactie van uploader (slot bezet of offline). Probeer een ander resultaat."))
                }
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e // normal cancel (user navigated away / cancelled) — don't emit Error
        } catch (e: Exception) {
            send(SlskDownloadState.Error(e.message ?: "Download mislukt"))
        } finally {
            runCatching { pConn?.close() }
            runCatching { server.close() }
        }
    }.flowOn(Dispatchers.IO)

    // Reads exactly [n] bytes from a raw peer stream (used for the transfer ticket).
    private fun readRaw(input: java.io.InputStream, n: Int): ByteArray {
        val buf = ByteArray(n)
        var off = 0
        while (off < n) {
            val r = input.read(buf, off, n - off)
            if (r < 0) break
            off += r
        }
        return buf
    }

    // ── Server message builders ────────────────────────────────────────────────

    private fun buildLogin(username: String, password: String): ByteArray =
        buildSlskMessage(1) {
            writeSlskString(username)
            writeSlskString(password)
            writeUInt32(160L) // version
            writeSlskString(md5hex(password))
            writeUInt32(17L)  // minor version
        }

    private fun buildSetWaitPort(port: Int): ByteArray =
        buildSlskMessage(2) { writeUInt32(port.toLong()) }

    private fun buildGetPeerAddress(peerUsername: String): ByteArray =
        buildSlskMessage(3) { writeSlskString(peerUsername) }

    private fun buildFileSearch(ticket: Int, query: String): ByteArray =
        buildSlskMessage(26) {
            writeUInt32(ticket.toLong())
            writeSlskString(query)
        }

    // Sent when WE respond to a server ConnectToPeer relay (the peer is waiting for this token).
    // Peer-init messages use a 1-byte code — see buildSlskInitMessage.
    private fun buildPierceFirewall(token: Long): ByteArray =
        buildSlskInitMessage(0) { writeUInt32(token) }

    // Sent when WE initiate a direct peer connection (downloads, etc.)
    private fun buildPeerInit(username: String, type: String, token: Long): ByteArray =
        buildSlskInitMessage(1) {
            writeSlskString(username)
            writeSlskString(type)
            writeUInt32(token)
        }

    private fun buildTransferRequest(direction: Int, ticket: Long, filename: String): ByteArray =
        buildSlskMessage(40) {
            writeUInt32(direction.toLong())
            writeUInt32(ticket)
            writeSlskString(filename)
        }

    // Polite "add me to your upload queue for this file" (PeerQueueUpload).
    private fun buildQueueUpload(filename: String): ByteArray =
        buildSlskMessage(43) { writeSlskString(filename) }

    // Our reply when a peer offers to upload (PeerTransferResponse): accept it.
    private fun buildTransferResponse(token: Long, allowed: Boolean): ByteArray =
        buildSlskMessage(41) {
            writeUInt32(token)
            writeUInt8(if (allowed) 1 else 0)
        }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private suspend fun loginServer(server: SlskSocket, username: String, password: String) {
        server.send(buildLogin(username, password))
        server.setSoTimeout(15_000)
        val loginData = readUntilCode(server, 1)
        val buf = ByteBuffer.wrap(loginData).order(ByteOrder.LITTLE_ENDIAN)
        val success = buf.readUInt8() != 0
        if (!success) {
            val reason = buf.readSlskString()
            error("Soulseek login failed: $reason")
        }
    }

    private suspend fun readUntilCode(socket: SlskSocket, targetCode: Int): ByteArray {
        repeat(30) {
            val msg = socket.readMessage()
            val buf = ByteBuffer.wrap(msg).order(ByteOrder.LITTLE_ENDIAN)
            val code = buf.readUInt32().toInt()
            if (code == targetCode) {
                return ByteArray(buf.remaining()).also { buf.get(it) }
            }
        }
        error("Did not receive expected message (code $targetCode)")
    }
}
