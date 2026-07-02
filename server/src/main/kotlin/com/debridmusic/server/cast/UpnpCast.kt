package com.debridmusic.server.cast

import org.slf4j.LoggerFactory
import org.w3c.dom.Element
import java.io.ByteArrayInputStream
import java.net.DatagramPacket
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.MulticastSocket
import java.net.URI
import java.net.URL
import javax.xml.parsers.DocumentBuilderFactory

/** A UPnP AV MediaRenderer on the LAN (Sonos speaker, DLNA renderer, etc.). */
data class Renderer(
    val id: String,           // stable-ish id derived from location host
    val name: String,
    val host: String,
    val avTransportUrl: String,
    val renderingControlUrl: String?,
)

/**
 * Minimal UPnP control point: discovers MediaRenderers via SSDP and drives them
 * with SOAP (SetAVTransportURI / Play / Pause / Stop / SetVolume). Standard UPnP,
 * so it speaks to Sonos and generic DLNA renderers alike. No external dependencies.
 */
class UpnpCast {
    private val log = LoggerFactory.getLogger(UpnpCast::class.java)
    private val SSDP_ADDR = "239.255.255.250"
    private val SSDP_PORT = 1900

    private val searchTargets = listOf(
        "urn:schemas-upnp-org:device:MediaRenderer:1",
        "urn:schemas-upnp-org:device:ZonePlayer:1",   // Sonos
    )

    /** Broadcast an M-SEARCH and collect responding renderers for [timeoutMs]. */
    fun discover(timeoutMs: Int = 2500): List<Renderer> {
        val locations = LinkedHashSet<String>()
        runCatching {
            MulticastSocket().use { sock ->
                sock.soTimeout = 400
                sock.reuseAddress = true
                val group = InetAddress.getByName(SSDP_ADDR)
                for (st in searchTargets) {
                    val msg = buildString {
                        append("M-SEARCH * HTTP/1.1\r\n")
                        append("HOST: $SSDP_ADDR:$SSDP_PORT\r\n")
                        append("MAN: \"ssdp:discover\"\r\n")
                        append("MX: 2\r\n")
                        append("ST: $st\r\n\r\n")
                    }.toByteArray()
                    repeat(2) { sock.send(DatagramPacket(msg, msg.size, InetSocketAddress(group, SSDP_PORT))) }
                }
                val deadline = System.currentTimeMillis() + timeoutMs
                val buf = ByteArray(2048)
                while (System.currentTimeMillis() < deadline) {
                    val pkt = DatagramPacket(buf, buf.size)
                    try {
                        sock.receive(pkt)
                        val text = String(pkt.data, 0, pkt.length)
                        text.lineSequence()
                            .firstOrNull { it.startsWith("LOCATION:", true) }
                            ?.substringAfter(':', "")?.trim()
                            ?.let { locations += it }
                    } catch (_: Exception) { /* soTimeout tick */ }
                }
            }
        }.onFailure { log.warn("SSDP discovery failed: {}", it.message) }

        val byHost = LinkedHashMap<String, Renderer>()
        for (loc in locations) {
            runCatching { describe(loc) }.getOrNull()?.let { byHost.putIfAbsent(it.host, it) }
        }
        return byHost.values.toList()
    }

    /** Fetch and parse a device description document into a [Renderer]. */
    private fun describe(location: String): Renderer? {
        val xml = httpGet(location) ?: return null
        val doc = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = false }
            .newDocumentBuilder().parse(ByteArrayInputStream(xml))
        val base = doc.getElementsByTagName("URLBase").item(0)?.textContent?.trim()
            ?.takeIf { it.isNotEmpty() } ?: URI(location).let { "${it.scheme}://${it.host}:${if (it.port > 0) it.port else 80}" }
        val rawName = doc.getElementsByTagName("friendlyName").item(0)?.textContent?.trim() ?: URI(location).host
        // Sonos reports "192.168.0.x - Sonos Move - RINCON_…"; keep just the friendly middle.
        val name = rawName
            .replace(Regex("^\\d+\\.\\d+\\.\\d+\\.\\d+\\s*-\\s*"), "")
            .replace(Regex("\\s*-\\s*RINCON_\\w+$"), "")
            .trim().ifEmpty { rawName }

        var avUrl: String? = null
        var rcUrl: String? = null
        val services = doc.getElementsByTagName("service")
        for (i in 0 until services.length) {
            val svc = services.item(i) as? Element ?: continue
            val type = svc.getElementsByTagName("serviceType").item(0)?.textContent.orEmpty()
            val ctrl = svc.getElementsByTagName("controlURL").item(0)?.textContent?.trim().orEmpty()
            if (ctrl.isEmpty()) continue
            val abs = if (ctrl.startsWith("http")) ctrl else base.trimEnd('/') + "/" + ctrl.trimStart('/')
            when {
                type.contains("AVTransport") -> avUrl = abs
                type.contains("RenderingControl") -> rcUrl = abs
            }
        }
        val av = avUrl ?: return null
        val host = URI(location).host
        return Renderer(id = host, name = name, host = host, avTransportUrl = av, renderingControlUrl = rcUrl)
    }

    // ── transport control ────────────────────────────────────────────────────
    fun playUrl(r: Renderer, mediaUrl: String, title: String, artist: String, album: String, mime: String) {
        val didl = didl(mediaUrl, title, artist, album, mime)
        soap(r.avTransportUrl, "AVTransport", "SetAVTransportURI",
            "<InstanceID>0</InstanceID><CurrentURI>${esc(mediaUrl)}</CurrentURI>" +
                "<CurrentURIMetaData>${esc(didl)}</CurrentURIMetaData>")
        soap(r.avTransportUrl, "AVTransport", "Play", "<InstanceID>0</InstanceID><Speed>1</Speed>")
    }

    fun play(r: Renderer)  = soap(r.avTransportUrl, "AVTransport", "Play", "<InstanceID>0</InstanceID><Speed>1</Speed>")
    fun pause(r: Renderer) = soap(r.avTransportUrl, "AVTransport", "Pause", "<InstanceID>0</InstanceID>")
    fun stop(r: Renderer)  = soap(r.avTransportUrl, "AVTransport", "Stop", "<InstanceID>0</InstanceID>")

    fun setVolume(r: Renderer, volume0to100: Int) {
        val url = r.renderingControlUrl ?: return
        soap(url, "RenderingControl", "SetVolume",
            "<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>${volume0to100.coerceIn(0, 100)}</DesiredVolume>")
    }

    // ── SOAP / HTTP plumbing ─────────────────────────────────────────────────
    private fun soap(controlUrl: String, service: String, action: String, argsXml: String): String {
        val serviceType = "urn:schemas-upnp-org:service:$service:1"
        val envelope =
            """<?xml version="1.0" encoding="utf-8"?>
               |<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
               |<s:Body><u:$action xmlns:u="$serviceType">$argsXml</u:$action></s:Body></s:Envelope>""".trimMargin()
        val conn = (URL(controlUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 4000; readTimeout = 6000
            doOutput = true
            setRequestProperty("Content-Type", "text/xml; charset=\"utf-8\"")
            setRequestProperty("SOAPACTION", "\"$serviceType#$action\"")
        }
        conn.outputStream.use { it.write(envelope.toByteArray()) }
        val code = conn.responseCode
        val body = (if (code in 200..299) conn.inputStream else conn.errorStream)?.readBytes()?.decodeToString().orEmpty()
        if (code !in 200..299) {
            log.warn("SOAP {} -> {}: {}", action, code, body.take(300))
            throw RuntimeException("Renderer rejected $action (HTTP $code)")
        }
        return body
    }

    private fun httpGet(url: String): ByteArray? =
        runCatching {
            val conn = (URL(url).openConnection() as HttpURLConnection).apply { connectTimeout = 3000; readTimeout = 4000 }
            conn.inputStream.use { it.readBytes() }
        }.getOrNull()

    private fun didl(url: String, title: String, artist: String, album: String, mime: String): String =
        """<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">""" +
            """<item id="dm-0" parentID="-1" restricted="1">""" +
            "<dc:title>${esc(title)}</dc:title><dc:creator>${esc(artist)}</dc:creator><upnp:album>${esc(album)}</upnp:album>" +
            "<upnp:class>object.item.audioItem.musicTrack</upnp:class>" +
            """<res protocolInfo="http-get:*:$mime:*">${esc(url)}</res></item></DIDL-Lite>"""

    private fun esc(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        .replace("\"", "&quot;").replace("'", "&apos;")
}
