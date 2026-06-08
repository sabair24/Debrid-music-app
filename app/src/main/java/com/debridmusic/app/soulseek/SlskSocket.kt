package com.debridmusic.app.soulseek

import com.debridmusic.app.soulseek.proto.writeUInt32
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder

class SlskSocket(private val host: String, private val port: Int) {
    private var socket: Socket? = null
    private var input: InputStream? = null
    private var output: OutputStream? = null

    val isConnected: Boolean get() = socket?.let { !it.isClosed && it.isConnected } ?: false

    suspend fun connect() = withContext(Dispatchers.IO) {
        val s = Socket(host, port)
        s.soTimeout = 30_000
        input = s.getInputStream()
        output = s.getOutputStream()
        socket = s
    }

    fun setSoTimeout(ms: Int) { socket?.soTimeout = ms }

    suspend fun send(bytes: ByteArray) = withContext(Dispatchers.IO) {
        output?.write(bytes)
        output?.flush()
    }

    // Send raw bytes without framing (for file transfer offset)
    suspend fun sendRaw(bytes: ByteArray) = send(bytes)

    // Returns the message payload: [4-byte code][data...]
    suspend fun readMessage(): ByteArray = withContext(Dispatchers.IO) {
        val lenBuf = ByteArray(4)
        readFully(lenBuf)
        val len = ByteBuffer.wrap(lenBuf).order(ByteOrder.LITTLE_ENDIAN).int.toLong() and 0xFFFFFFFFL
        val payload = ByteArray(len.toInt().coerceAtMost(4 * 1024 * 1024)) // max 4 MB per message
        readFully(payload)
        payload
    }

    fun rawInputStream(): InputStream = input ?: throw EOFException("Not connected")

    private fun readFully(buf: ByteArray) {
        val inp = input ?: throw EOFException("Not connected")
        var offset = 0
        while (offset < buf.size) {
            val n = inp.read(buf, offset, buf.size - offset)
            if (n < 0) throw EOFException("Connection closed by peer")
            offset += n
        }
    }

    fun close() {
        runCatching { socket?.close() }
        socket = null; input = null; output = null
    }
}
