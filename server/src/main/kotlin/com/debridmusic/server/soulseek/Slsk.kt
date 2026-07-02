package com.debridmusic.server.soulseek

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.zip.Inflater

/** Little-endian wire writer for Soulseek messages. */
class SlskWriter {
    private val out = ByteArrayOutputStream()
    fun u8(v: Int) = apply { out.write(v and 0xFF) }
    fun u32(v: Long) = apply {
        out.write((v and 0xFF).toInt()); out.write(((v shr 8) and 0xFF).toInt())
        out.write(((v shr 16) and 0xFF).toInt()); out.write(((v shr 24) and 0xFF).toInt())
    }
    fun u32(v: Int) = u32(v.toLong())
    fun u64(v: Long) = apply { u32(v and 0xFFFFFFFFL); u32((v ushr 32) and 0xFFFFFFFFL) }
    fun str(s: String) = apply { val b = s.toByteArray(Charsets.UTF_8); u32(b.size); out.write(b) }
    fun bool(b: Boolean) = u8(if (b) 1 else 0)
    fun bytes(): ByteArray = out.toByteArray()
}

/** Little-endian wire reader over a message payload. */
class SlskReader(data: ByteArray) {
    private val bb = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
    fun remaining() = bb.remaining()
    fun u8(): Int = bb.get().toInt() and 0xFF
    fun u32(): Long {
        val b0 = bb.get().toLong() and 0xFF; val b1 = bb.get().toLong() and 0xFF
        val b2 = bb.get().toLong() and 0xFF; val b3 = bb.get().toLong() and 0xFF
        return b0 or (b1 shl 8) or (b2 shl 16) or (b3 shl 24)
    }
    fun u64(): Long { val lo = u32(); val hi = u32(); return lo or (hi shl 32) }
    fun str(): String {
        if (bb.remaining() < 4) return ""
        val len = u32().toInt().coerceIn(0, bb.remaining())
        val b = ByteArray(len); bb.get(b); return String(b, Charsets.UTF_8)
    }
    fun bool(): Boolean = u8() != 0
    /** Soulseek stores IPv4 as 4 LE bytes; the dotted string reverses them. */
    fun ip(): String { val b0 = u8(); val b1 = u8(); val b2 = u8(); val b3 = u8(); return "$b3.$b2.$b1.$b0" }
}

object Slsk {
    /** Server + regular peer message: [u32 len][u32 code][payload]. len counts the code. */
    fun message(code: Int, payload: ByteArray): ByteArray =
        SlskWriter().u32(4 + payload.size).u32(code).bytes() + payload

    /** Peer-INIT message: [u32 len][u8 code][payload]. The code is ONE byte here. */
    fun initMessage(code: Int, payload: ByteArray): ByteArray =
        SlskWriter().u32(1 + payload.size).u8(code).bytes() + payload

    fun md5hex(s: String): String =
        MessageDigest.getInstance("MD5").digest(s.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    /** zlib (RFC-1950) inflate; returns the input unchanged if it isn't compressed. */
    fun zlibDecompress(data: ByteArray): ByteArray {
        return try {
            val inflater = Inflater()
            inflater.setInput(data)
            val out = ByteArrayOutputStream(data.size * 4)
            val buf = ByteArray(8192)
            while (!inflater.finished() && inflater.totalIn < data.size) {
                val n = inflater.inflate(buf)
                if (n == 0) break
                out.write(buf, 0, n)
            }
            inflater.end()
            val result = out.toByteArray()
            if (result.isEmpty()) data else result
        } catch (e: Exception) { data }
    }
}
