package com.debridmusic.server.util

import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface

/** Helpers for figuring out how devices on the LAN should reach this server. */
object NetworkInfo {

    /** All usable (up, non-loopback) IPv4 addresses on this machine, best candidates first. */
    private fun candidates(): List<Inet4Address> =
        runCatching {
            NetworkInterface.getNetworkInterfaces().asSequence()
                .filter { it.isUp && !it.isLoopback }
                .sortedBy { if (isVirtual(it)) 1 else 0 }   // real adapters before virtual ones
                .flatMap { it.inetAddresses.asSequence() }
                .filterIsInstance<Inet4Address>()
                .filter { !it.isLoopbackAddress && it.isSiteLocalAddress }
                .filter { it.hostAddress != null && !it.hostAddress.startsWith("192.168.56.") } // VirtualBox host-only
                .toList()
        }.getOrDefault(emptyList())

    private fun isVirtual(nif: NetworkInterface): Boolean {
        val n = (nif.displayName + " " + nif.name).lowercase()
        return nif.isVirtual || listOf("virtual", "vbox", "hyper-v", "vethernet", "vmware", "docker", "wsl", "loopback")
            .any { it in n }
    }

    /** Best-guess LAN IPv4 for this machine (Sonos/Shield can't reach localhost/0.0.0.0). */
    fun lanIpv4(): String? = candidates().firstOrNull()?.hostAddress

    /**
     * Local IPv4 on the same /24 as [targetHost] — so a stream URL we hand a speaker
     * is on a network that speaker is actually on. Falls back to [lanIpv4].
     */
    fun lanIpv4For(targetHost: String): String? {
        val target = runCatching { InetAddress.getByName(targetHost).address }.getOrNull()
        if (target != null && target.size == 4) {
            candidates().firstOrNull {
                val a = it.address
                a.size == 4 && a[0] == target[0] && a[1] == target[1] && a[2] == target[2]
            }?.let { return it.hostAddress }
        }
        return lanIpv4()
    }

    fun lanBaseUrl(port: Int): String = "http://${lanIpv4() ?: "127.0.0.1"}:$port"

    /** LAN base URL guaranteed reachable from a device at [targetHost]. */
    fun lanBaseUrlFor(targetHost: String, port: Int): String = "http://${lanIpv4For(targetHost) ?: "127.0.0.1"}:$port"
}
