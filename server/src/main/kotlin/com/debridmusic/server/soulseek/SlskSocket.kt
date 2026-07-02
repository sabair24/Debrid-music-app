package com.debridmusic.server.soulseek

import java.io.DataInputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket

/** Thin TCP wrapper for the Soulseek protocol (little-endian, length-prefixed frames). */
class SlskSocket(host: String, port: Int, connectTimeoutMs: Int = 6000) : AutoCloseable {
    private val socket = Socket()
    private val input: DataInputStream
    private val output: OutputStream

    init {
        socket.connect(InetSocketAddress(host, port), connectTimeoutMs)
        socket.soTimeout = 30_000
        input = DataInputStream(socket.getInputStream())
        output = socket.getOutputStream()
    }

    fun setSoTimeout(ms: Int) { socket.soTimeout = ms }

    fun send(bytes: ByteArray) { output.write(bytes); output.flush() }

    /** Read one framed message; returns its payload ([code][data…]). */
    fun readMessage(): ByteArray {
        val lenBytes = ByteArray(4); input.readFully(lenBytes)
        var len = (lenBytes[0].toLong() and 0xFF) or ((lenBytes[1].toLong() and 0xFF) shl 8) or
            ((lenBytes[2].toLong() and 0xFF) shl 16) or ((lenBytes[3].toLong() and 0xFF) shl 24)
        len = len and 0xFFFFFFFFL
        // Clamp on the Long first — a length ≥ 0x80000000 would go negative after toInt().
        val n = len.coerceIn(0, 4L * 1024 * 1024).toInt()
        val payload = ByteArray(n); input.readFully(payload); return payload
    }

    fun rawInputStream(): InputStream = input
    fun readRaw(n: Int): ByteArray { val b = ByteArray(n); input.readFully(b); return b }
    fun sendRaw(bytes: ByteArray) { output.write(bytes); output.flush() }

    override fun close() { runCatching { socket.close() } }
}
