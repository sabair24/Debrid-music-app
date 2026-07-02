package com.debridmusic.server.soulseek

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.slf4j.LoggerFactory
import java.io.EOFException
import java.io.File
import java.net.SocketTimeoutException
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import kotlin.random.Random

sealed interface SlskResult {
    data class Done(val path: String) : SlskResult
    data class Fail(val reason: String) : SlskResult
}

/**
 * Soulseek P2P client (server-relayed, firewalled mode — WaitPort=0). Search issues a
 * FileSearch and collects results from peers the server tells us to connect out to;
 * download negotiates on a "P" connection and receives bytes on a server-relayed "F"
 * connection. Ported verbatim from the app's working protocol logic.
 */
class SoulseekClient {
    private val log = LoggerFactory.getLogger(SoulseekClient::class.java)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val ticketGen = AtomicInteger(Random.nextInt(10_000, 999_999))

    private fun now() = System.currentTimeMillis()
    private fun codeOf(payload: ByteArray) = SlskReader(payload).u32().toInt()
    private fun bodyOf(payload: ByteArray) = if (payload.size > 4) payload.copyOfRange(4, payload.size) else ByteArray(0)

    // ── shared: login + read helper ─────────────────────────────────────────────
    private fun loginServer(server: SlskSocket, username: String, password: String) {
        val login = SlskWriter().str(username).str(password).u32(160)
            .str(Slsk.md5hex(password)).u32(17).bytes()
        server.send(Slsk.message(1, login))
        server.setSoTimeout(15_000)
        val body = readUntilCode(server, 1)
        val r = SlskReader(body)
        val success = r.u8() != 0
        if (!success) error("Soulseek login geweigerd: ${r.str()}")
    }

    /** Reads framed messages until one matches [wantCode]; returns that message's body (after the code). */
    private fun readUntilCode(server: SlskSocket, wantCode: Int): ByteArray {
        repeat(30) {
            val payload = server.readMessage()
            if (codeOf(payload) == wantCode) return bodyOf(payload)
        }
        error("Verwacht server-bericht $wantCode niet ontvangen")
    }

    // ── search ──────────────────────────────────────────────────────────────────
    suspend fun search(username: String, password: String, query: String): List<SoulseekFile> =
        withContext(Dispatchers.IO) {
            val ticket = ticketGen.incrementAndGet()
            val results = CopyOnWriteArrayList<SoulseekFile>()
            val peerJobs = CopyOnWriteArrayList<Job>()
            SlskSocket(SERVER_HOST, SERVER_PORT).use { server ->
                loginServer(server, username, password)
                server.send(Slsk.message(2, SlskWriter().u32(0).bytes()))                 // SetWaitPort(0)
                server.send(Slsk.message(26, SlskWriter().u32(ticket).str(query).bytes())) // FileSearch

                val deadline = now() + 14_000
                val softMin = now() + 5_000
                while (true) {
                    val remaining = deadline - now()
                    if (remaining <= 0 || results.size >= 200) break
                    if (results.size >= EARLY_TARGET && now() >= softMin) break
                    server.setSoTimeout(remaining.coerceIn(200, 60_000).toInt())
                    val payload = try { server.readMessage() } catch (e: SocketTimeoutException) { break } catch (e: EOFException) { break }
                    if (codeOf(payload) != 18) continue                                     // ConnectToPeer only
                    val r = SlskReader(bodyOf(payload))
                    r.str(); val type = r.str(); val ip = r.ip(); val port = r.u32().toInt(); val token = r.u32()
                    if (type == "P" && ip != "0.0.0.0" && port > 0 && peerJobs.size < 50) {
                        peerJobs += scope.launch { collectPeerResults(ip, port, token, ticket, results) }
                    }
                }
                withTimeoutOrNull(8_000) { while (peerJobs.any { it.isActive } && results.size < EARLY_TARGET) delay(150) }
                peerJobs.forEach { it.cancel() }
            }
            results.filter { it.isAudio }.sortedWith(
                compareByDescending<SoulseekFile> { if (it.isFlac) 1 else 0 }
                    .thenByDescending { it.freeSlots }.thenByDescending { it.speed }.thenByDescending { it.size },
            )
        }

    private fun collectPeerResults(ip: String, port: Int, token: Long, ticket: Int, results: MutableList<SoulseekFile>) {
        runCatching {
            SlskSocket(ip, port, 5_000).use { peer ->
                peer.setSoTimeout(5_000)
                peer.send(Slsk.initMessage(0, SlskWriter().u32(token).bytes()))            // PierceFirewall
                repeat(10) {
                    val payload = peer.readMessage()
                    if (codeOf(payload) == 9) {                                            // SearchResults
                        parseSearchResults(Slsk.zlibDecompress(bodyOf(payload)), ticket, results)
                        return
                    }
                }
            }
        }
    }

    private fun parseSearchResults(data: ByteArray, ticket: Int, results: MutableList<SoulseekFile>) {
        val r = SlskReader(data)
        val peerUser = r.str()
        if (r.u32().toInt() != ticket) return
        val count = r.u32().toInt().coerceIn(0, 200)
        val files = ArrayList<SoulseekFile>(count)
        repeat(count) {
            if (r.remaining() < 5) return@repeat
            r.u8()                                                                        // entry type (1=file)
            val filename = r.str()
            val size = r.u64()
            r.str()                                                                       // legacy extension, discard
            val numAttr = r.u32().toInt().coerceIn(0, 10)
            var bitrate: Int? = null; var dur: Int? = null; var vbr = false; var sampleRate: Int? = null; var bitDepth: Int? = null
            repeat(numAttr) {
                val t = r.u32().toInt(); val v = r.u32().toInt()
                when (t) { 0 -> bitrate = v; 1 -> dur = v; 2 -> vbr = v != 0; 4 -> sampleRate = v; 5 -> bitDepth = v }
            }
            files += SoulseekFile(peerUser, filename, size, bitrate = bitrate, durationSec = dur, sampleRate = sampleRate, bitDepth = bitDepth, isVbr = vbr)
        }
        val freeSlots = if (r.remaining() > 0) r.bool() else false
        val speed = if (r.remaining() >= 4) r.u32().toInt() else 0
        val queueLen = if (r.remaining() >= 4) r.u32().toInt() else 0
        files.forEach { results += it.copy(freeSlots = freeSlots, speed = speed, queueLength = queueLen) }
    }

    // ── download ─────────────────────────────────────────────────────────────────
    suspend fun download(username: String, password: String, file: SoulseekFile, destFile: File, onProgress: (Long, Long) -> Unit): SlskResult =
        withContext(Dispatchers.IO) {
            val fileSize = AtomicLong(0)
            val denyReason = AtomicReference<String?>(null)
            val delivered = AtomicBoolean(false)
            runCatching {
                SlskSocket(SERVER_HOST, SERVER_PORT).use { server ->
                    loginServer(server, username, password)
                    server.send(Slsk.message(2, SlskWriter().u32(0).bytes()))              // SetWaitPort(0)
                    server.send(Slsk.message(3, SlskWriter().str(file.username).bytes()))   // GetPeerAddress
                    server.setSoTimeout(10_000)
                    val ar = SlskReader(readUntilCode(server, 3))
                    ar.str(); val peerIp = ar.ip(); val peerPort = ar.u32().toInt()
                    if (peerIp == "0.0.0.0" || peerPort == 0) return@withContext SlskResult.Fail("Uploader niet bereikbaar (firewalled)")

                    val dlToken = ticketGen.incrementAndGet().toLong()
                    SlskSocket(peerIp, peerPort, 8_000).use { peer ->
                        peer.send(Slsk.initMessage(1, SlskWriter().str(username).str("P").u32(dlToken).bytes())) // PeerInit "P"
                        peer.send(Slsk.message(43, SlskWriter().str(file.filename).bytes()))                     // QueueUpload
                        peer.send(Slsk.message(40, SlskWriter().u32(0).u32(dlToken).str(file.filename).bytes())) // TransferRequest
                        onProgress(0, 0)

                        val pJob = scope.launch {
                            runCatching {
                                peer.setSoTimeout(60_000)
                                repeat(40) {
                                    val payload = peer.readMessage()
                                    val r = SlskReader(bodyOf(payload))
                                    when (codeOf(payload)) {
                                        41 -> { r.u32(); if (r.bool()) fileSize.compareAndSet(0, r.u64()) else denyReason.set(r.str()) }
                                        40 -> { r.u32(); val tok = r.u32().toInt(); r.str(); if (r.remaining() >= 8) fileSize.compareAndSet(0, r.u64()); peer.send(Slsk.message(41, SlskWriter().u32(tok).u8(1).bytes())) }
                                    }
                                }
                            }
                        }

                        val deadline = now() + 90_000
                        while (!delivered.get() && now() < deadline) {
                            server.setSoTimeout((deadline - now()).coerceIn(500, 60_000).toInt())
                            val payload = try { server.readMessage() } catch (e: SocketTimeoutException) { continue } catch (e: EOFException) { break }
                            if (codeOf(payload) != 18) continue
                            val r = SlskReader(bodyOf(payload))
                            r.str(); val type = r.str(); val ip = r.ip(); val port = r.u32().toInt(); val ctpToken = r.u32()
                            if (type != "F" || ip == "0.0.0.0" || port <= 0) continue
                            streamFile(ip, port, ctpToken, fileSize.get(), destFile, onProgress, delivered)
                        }
                        pJob.cancel()
                    }
                }
                if (delivered.get()) return@withContext SlskResult.Done(destFile.absolutePath)
                val reason = denyReason.get()
                when {
                    reason?.contains("Queued", ignoreCase = true) == true -> SlskResult.Fail("In wachtrij bij uploader")
                    reason != null -> SlskResult.Fail("Geweigerd door uploader: $reason")
                    else -> SlskResult.Fail("Geen reactie van uploader (slot bezet of offline)")
                }
            }.getOrElse { SlskResult.Fail(it.message ?: "Download mislukt") }
        }

    private fun streamFile(ip: String, port: Int, ctpToken: Long, total: Long, destFile: File, onProgress: (Long, Long) -> Unit, delivered: AtomicBoolean) {
        runCatching {
            SlskSocket(ip, port, 8_000).use { f ->
                f.send(Slsk.initMessage(0, SlskWriter().u32(ctpToken).bytes()))            // PierceFirewall
                f.setSoTimeout(45_000)
                val inp = f.rawInputStream()
                f.readRaw(4)                                                               // transfer ticket, discard
                f.sendRaw(ByteArray(8))                                                     // offset = 0
                destFile.parentFile?.mkdirs()
                var received = 0L; var lastEmit = 0L
                destFile.outputStream().buffered(262_144).use { out ->
                    val buf = ByteArray(262_144)
                    while (true) {
                        if (total > 0 && received >= total) break
                        val n = inp.read(buf); if (n < 0) break
                        out.write(buf, 0, n); received += n
                        if (received - lastEmit >= 1_000_000) { lastEmit = received; onProgress(received, total) }
                    }
                }
                if (received > 0 && (total == 0L || received >= total)) {
                    delivered.set(true); onProgress(received, if (total > 0) total else received)
                } else destFile.delete()
            }
        }.onFailure { log.warn("F-transfer failed: {}", it.message) }
    }

    companion object {
        const val SERVER_HOST = "server.slsknet.org"
        const val SERVER_PORT = 2242
        const val EARLY_TARGET = 40
    }
}
