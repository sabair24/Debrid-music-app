package com.debridmusic.app.soulseek.proto

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.zip.Inflater

// ── Write ─────────────────────────────────────────────────────────────────────

fun ByteArrayOutputStream.writeUInt8(v: Int) { write(v and 0xFF) }

fun ByteArrayOutputStream.writeUInt32(v: Long) {
    write((v and 0xFF).toInt())
    write(((v shr 8) and 0xFF).toInt())
    write(((v shr 16) and 0xFF).toInt())
    write(((v shr 24) and 0xFF).toInt())
}

fun ByteArrayOutputStream.writeUInt64(v: Long) {
    writeUInt32(v and 0xFFFFFFFFL)
    writeUInt32((v ushr 32) and 0xFFFFFFFFL)
}

fun ByteArrayOutputStream.writeSlskString(s: String) {
    val bytes = s.toByteArray(Charsets.UTF_8)
    writeUInt32(bytes.size.toLong())
    write(bytes)
}

// ── Read ──────────────────────────────────────────────────────────────────────

fun ByteBuffer.readUInt8(): Int = (get().toInt() and 0xFF)

fun ByteBuffer.readUInt32(): Long {
    val b0 = readUInt8().toLong()
    val b1 = readUInt8().toLong()
    val b2 = readUInt8().toLong()
    val b3 = readUInt8().toLong()
    return b0 or (b1 shl 8) or (b2 shl 16) or (b3 shl 24)
}

fun ByteBuffer.readUInt64(): Long {
    val lo = readUInt32()
    val hi = readUInt32()
    return lo or (hi shl 32)
}

fun ByteBuffer.readSlskString(): String {
    if (remaining() < 4) return ""
    val len = readUInt32().toInt().coerceIn(0, remaining())
    val bytes = ByteArray(len)
    get(bytes)
    return String(bytes, Charsets.UTF_8)
}

fun ByteBuffer.readBool(): Boolean = readUInt8() != 0

// Soulseek stores IP as 4 LE bytes where byte order reverses the dotted notation
fun ByteBuffer.readSlskIp(): String {
    val b0 = readUInt8()
    val b1 = readUInt8()
    val b2 = readUInt8()
    val b3 = readUInt8()
    return "$b3.$b2.$b1.$b0"
}

// ── Message framing ───────────────────────────────────────────────────────────

fun buildSlskMessage(code: Int, block: ByteArrayOutputStream.() -> Unit): ByteArray {
    val payload = ByteArrayOutputStream().apply {
        writeUInt32(code.toLong())
        block()
    }.toByteArray()
    return ByteArrayOutputStream().apply {
        writeUInt32(payload.size.toLong())
        write(payload)
    }.toByteArray()
}

// Peer INIT messages (PierceFirewall=0, PeerInit=1) use a SINGLE-BYTE code,
// unlike server and regular peer messages which use a 4-byte code. Writing the
// code as 4 bytes shifts every following field by 3 bytes, so the peer reads a
// corrupt token and silently drops the connection (symptom: peers connect but
// never send a reply — peer_msg: 0).
fun buildSlskInitMessage(code: Int, block: ByteArrayOutputStream.() -> Unit): ByteArray {
    val payload = ByteArrayOutputStream().apply {
        writeUInt8(code)
        block()
    }.toByteArray()
    return ByteArrayOutputStream().apply {
        writeUInt32(payload.size.toLong())
        write(payload)
    }.toByteArray()
}

// ── Utilities ─────────────────────────────────────────────────────────────────

fun md5hex(s: String): String =
    MessageDigest.getInstance("MD5").digest(s.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }

fun tryZlibDecompress(data: ByteArray): ByteArray = try {
    val inf = Inflater()
    inf.setInput(data)
    val out = ByteArrayOutputStream(data.size * 4)
    val buf = ByteArray(8192)
    while (!inf.finished() && inf.totalIn < data.size) {
        val n = inf.inflate(buf)
        if (n == 0) break
        out.write(buf, 0, n)
    }
    inf.end()
    out.toByteArray().takeIf { it.isNotEmpty() } ?: data
} catch (_: Exception) { data }
