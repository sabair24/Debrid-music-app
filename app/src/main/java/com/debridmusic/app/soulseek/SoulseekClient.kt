package com.debridmusic.app.soulseek

import android.content.Context
import com.debridmusic.app.soulseek.proto.*
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
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
            val peerConnected = AtomicInteger(0)          // peers we successfully connected to

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
                val deadline = System.currentTimeMillis() + 14_000L

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

                            if (type == "P" && ip != "0.0.0.0" && port > 0 && peerJobs.size < 12) {
                                val job = CoroutineScope(Dispatchers.IO).launch {
                                    collectPeerResults(username, ip, port, token, ticket, results, peerConnected)
                                }
                                peerJobs.add(job)
                            }
                        }
                    }
                }

                // Wait for in-flight peer connections to finish (generous budget)
                withTimeoutOrNull(10_000L) { peerJobs.forEach { it.join() } }
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
                    "ruw: ${results.size}")
            }
            audioResults
        }
    }

    private suspend fun collectPeerResults(
        ourUsername: String,
        ip: String,
        port: Int,
        token: Long,
        ticket: Int,
        results: CopyOnWriteArrayList<SoulseekFile>,
        peerConnected: AtomicInteger,
    ) {
        val peer = SlskSocket(ip, port)
        try {
            peer.connect(connectTimeoutMs = 5_000)
            peerConnected.incrementAndGet()
            peer.setSoTimeout(8_000)
            // ConnectToPeer flow: send PierceFirewall (code 0) with the server-relayed
            // token so the peer can match this connection to their pending search result.
            // PeerInit (code 1) is only for connections WE initiate without the server relay.
            peer.send(buildPierceFirewall(token))

            repeat(8) {
                val msg = try { peer.readMessage() } catch (_: Exception) { return }
                val buf = ByteBuffer.wrap(msg).order(ByteOrder.LITTLE_ENDIAN)
                val code = buf.readUInt32().toInt()

                if (code == 9) { // SearchResults
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
    ): Flow<SlskDownloadState> = flow {
        // 1. Get peer address from server
        val server = SlskSocket(SERVER_HOST, SERVER_PORT)
        try {
            server.connect()
            loginServer(server, username, password)
            server.send(buildSetWaitPort(0))
            server.send(buildGetPeerAddress(file.username))
            server.setSoTimeout(10_000)

            val addrData = readUntilCode(server, 3)
            val addrBuf = ByteBuffer.wrap(addrData).order(ByteOrder.LITTLE_ENDIAN)
            addrBuf.readSlskString() // peer username
            val peerIp = addrBuf.readSlskIp()
            val peerPort = addrBuf.readUInt32().toInt()

            if (peerIp == "0.0.0.0" || peerPort == 0) error("Peer is offline or unreachable")
            server.close()

            // 2. Connect to peer and request file
            val peer = SlskSocket(peerIp, peerPort)
            peer.connect()
            peer.setSoTimeout(20_000)

            val dlToken = ticketGen.incrementAndGet().toLong()
            peer.send(buildPeerInit(username, "P", dlToken))
            peer.send(buildTransferRequest(0, dlToken, file.filename))

            // Read up to 5 messages looking for TransferResponse (code 41)
            var fileSize = 0L
            var transferAllowed = false
            var denyReason = "No response"

            repeat(5) {
                if (transferAllowed) return@repeat
                val msg = try { peer.readMessage() } catch (_: Exception) { return@repeat }
                val buf = ByteBuffer.wrap(msg).order(ByteOrder.LITTLE_ENDIAN)
                val code = buf.readUInt32().toInt()
                if (code == 41) { // TransferResponse
                    buf.readUInt32() // token
                    transferAllowed = buf.readBool()
                    if (transferAllowed) {
                        fileSize = buf.readUInt64()
                    } else {
                        denyReason = buf.readSlskString()
                    }
                }
            }

            if (!transferAllowed) {
                peer.close()
                if (denyReason.contains("Queued", ignoreCase = true)) {
                    emit(SlskDownloadState.Queued(denyReason))
                } else {
                    error("Transfer denied: $denyReason")
                }
                return@flow
            }

            // 3. Send offset (0 = from start), then stream file bytes
            peer.sendRaw(ByteArray(8)) // 8-byte LE uint64 = 0
            peer.setSoTimeout(60_000)

            val ext = file.extension.ifBlank { "tmp" }
            val tempFile = File(context.cacheDir, "slsk_${System.currentTimeMillis()}.$ext")
            var received = 0L
            var lastEmit = 0L

            val inp = peer.rawInputStream()
            tempFile.outputStream().use { out ->
                val buf = ByteArray(65_536)
                while (received < fileSize || fileSize == 0L) {
                    val toRead = if (fileSize > 0) minOf(buf.size.toLong(), fileSize - received).toInt()
                                 else buf.size
                    val n = inp.read(buf, 0, toRead)
                    if (n < 0) break
                    out.write(buf, 0, n)
                    received += n
                    // Emit progress at most every 256 KB
                    if (received - lastEmit >= 262_144L || received >= fileSize) {
                        emit(SlskDownloadState.Downloading(received, fileSize))
                        lastEmit = received
                    }
                    if (fileSize > 0 && received >= fileSize) break
                }
            }

            peer.close()

            if (fileSize == 0L || received >= fileSize) {
                emit(SlskDownloadState.Done(tempFile.absolutePath))
            } else {
                tempFile.delete()
                error("Incomplete download: $received / $fileSize bytes")
            }

        } catch (e: Exception) {
            server.close()
            emit(SlskDownloadState.Error(e.message ?: "Download failed"))
        }
    }.flowOn(Dispatchers.IO)

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

    // Sent when WE respond to a server ConnectToPeer relay (the peer is waiting for this token)
    private fun buildPierceFirewall(token: Long): ByteArray =
        buildSlskMessage(0) { writeUInt32(token) }

    // Sent when WE initiate a direct peer connection (downloads, etc.)
    private fun buildPeerInit(username: String, type: String, token: Long): ByteArray =
        buildSlskMessage(1) {
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
