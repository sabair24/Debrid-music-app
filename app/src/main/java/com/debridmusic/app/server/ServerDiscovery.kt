package com.debridmusic.app.server

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import javax.inject.Inject
import javax.inject.Singleton

/** A DebridMusic PC that answered on this network. */
data class DiscoveredServer(
    val name: String,
    val host: String,
    val port: Int,
) {
    val baseUrl: String get() = "http://$host:$port"
}

/**
 * Finds the PC on the network, so nothing has to be typed on a TV remote.
 *
 * Two mechanisms, because neither is reliable on its own here. Bonjour/mDNS is the proper one and
 * is what [NsdManager] speaks — but the advertising side is a Dart package whose Windows support
 * grew out of a prototype, and a Shield on a mesh network doesn't always see multicast anyway.
 * So a plain UDP broadcast probe runs beside it. Whichever answers first is used; if both do, the
 * duplicates collapse on host.
 */
@Singleton
class ServerDiscovery @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val nsdManager: NsdManager? by lazy {
        runCatching { context.getSystemService(Context.NSD_SERVICE) as NsdManager }.getOrNull()
    }

    suspend fun discover(timeoutMs: Long = 4000): List<DiscoveredServer> = withContext(Dispatchers.IO) {
        val found = LinkedHashMap<String, DiscoveredServer>()
        // Broadcast first: it answers in milliseconds on a flat home network, where mDNS
        // resolution can take seconds.
        broadcastProbe(timeoutMs / 2).forEach { found.putIfAbsent(it.host, it) }
        if (found.isEmpty()) {
            mdnsProbe(timeoutMs).forEach { found.putIfAbsent(it.host, it) }
        }
        found.values.toList()
    }

    /** Shout on the LAN and collect whoever says they're DebridMusic. */
    private fun broadcastProbe(timeoutMs: Long): List<DiscoveredServer> {
        val out = mutableListOf<DiscoveredServer>()
        try {
            DatagramSocket().use { socket ->
                socket.broadcast = true
                socket.soTimeout = 400
                val payload = PROBE.toByteArray()
                socket.send(
                    DatagramPacket(
                        payload, payload.size,
                        InetSocketAddress(InetAddress.getByName("255.255.255.255"), DISCOVERY_PORT),
                    )
                )
                val deadline = System.currentTimeMillis() + timeoutMs
                val buffer = ByteArray(2048)
                while (System.currentTimeMillis() < deadline) {
                    val packet = DatagramPacket(buffer, buffer.size)
                    try {
                        socket.receive(packet)
                    } catch (_: IOException) {
                        continue // soTimeout tick — keep listening until the deadline
                    }
                    val body = String(packet.data, 0, packet.length)
                    if (!body.contains("debridmusic")) continue
                    val port = PORT_RE.find(body)?.groupValues?.get(1)?.toIntOrNull() ?: DISCOVERY_PORT
                    val name = NAME_RE.find(body)?.groupValues?.get(1) ?: packet.address.hostAddress.orEmpty()
                    out += DiscoveredServer(name, packet.address.hostAddress.orEmpty(), port)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "broadcast discovery failed: ${e.message}")
        }
        return out
    }

    private suspend fun mdnsProbe(timeoutMs: Long): List<DiscoveredServer> {
        val manager = nsdManager ?: return emptyList()
        val found = mutableListOf<DiscoveredServer>()
        val first = CompletableDeferred<Unit>()

        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) = Unit
            override fun onDiscoveryStopped(type: String) = Unit
            override fun onStartDiscoveryFailed(type: String, code: Int) {
                if (!first.isCompleted) first.complete(Unit)
            }
            override fun onStopDiscoveryFailed(type: String, code: Int) = Unit
            override fun onServiceLost(info: NsdServiceInfo) = Unit

            override fun onServiceFound(info: NsdServiceInfo) {
                // Resolving is a second round trip; only the host and port it yields are usable.
                @Suppress("DEPRECATION")
                manager.resolveService(info, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(failed: NsdServiceInfo, code: Int) = Unit
                    override fun onServiceResolved(resolved: NsdServiceInfo) {
                        @Suppress("DEPRECATION")
                        val host = resolved.host?.hostAddress ?: return
                        synchronized(found) {
                            if (found.none { it.host == host }) {
                                found += DiscoveredServer(resolved.serviceName, host, resolved.port)
                            }
                        }
                        if (!first.isCompleted) first.complete(Unit)
                    }
                })
            }
        }

        return try {
            manager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
            withTimeoutOrNull(timeoutMs) { first.await() }
            // A moment more, so a second PC on the network isn't cut off by the first answer.
            kotlinx.coroutines.delay(400)
            synchronized(found) { found.toList() }
        } catch (e: TimeoutCancellationException) {
            emptyList()
        } catch (e: Exception) {
            Log.w(TAG, "mDNS discovery failed: ${e.message}")
            emptyList()
        } finally {
            runCatching { manager.stopServiceDiscovery(listener) }
        }
    }

    companion object {
        private const val TAG = "ServerDiscovery"
        const val SERVICE_TYPE = "_debridmusic._tcp."
        const val DISCOVERY_PORT = 47820
        const val PROBE = "DEBRIDMUSIC?"
        private val PORT_RE = """"port"\s*:\s*(\d+)""".toRegex()
        private val NAME_RE = """"name"\s*:\s*"([^"]*)"""".toRegex()
    }
}
