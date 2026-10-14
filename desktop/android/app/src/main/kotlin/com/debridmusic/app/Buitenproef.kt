package com.debridmusic.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager

/**
 * "Test buitenverbinding" (stap 8.2 van "verbinden zoals Roon ARC", 14-10-2026): een paar verzoeken
 * over MOBIELE DATA, ook als wifi aan staat — zoals de pc er van buiten uitziet.
 *
 * Thuis kan de eigen deur niet getoetst worden langs wifi: het publieke adres vanaf het eigen netwerk
 * proberen gaat via de modem zelf (hairpin), en dat zegt niets over buiten. Via mobiele data wel.
 *
 * Elk doel krijgt een antwoord: "antwoordt" (200), "status:<n>" (iets antwoordde, met een andere code),
 * "ander-certificaat" (iets met TLS, maar niet onze pc) of "geen" (niets). De versleutelde doelen worden
 * vastgepind op de pin van de pc; er is geen naam om na te kijken, de pin beslist.
 *
 * Altijd afmelden: een aangevraagd netwerk dat blijft hangen, houdt de mobiele radio wakker.
 */
object Buitenproef {
    private val hoofd = Handler(Looper.getMainLooper())

    fun proef(context: Context, doelen: List<String>, pin: String, klaar: (Map<String, String>) -> Unit) {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val eenKeer = AtomicBoolean(false)
        fun meld(uit: Map<String, String>) {
            if (eenKeer.compareAndSet(false, true)) hoofd.post { klaar(uit) }
        }
        val vraag = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        val terug = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val zelf = this
                // Alle doelen tegelijk: elk kan op mobiel tien seconden op een time-out wachten.
                Thread {
                    val pool = Executors.newFixedThreadPool(doelen.size.coerceAtLeast(1))
                    val uit = ConcurrentHashMap<String, String>()
                    val taken = doelen.map { doel -> pool.submit { uit[doel] = probeer(network, doel, pin) } }
                    for (t in taken) {
                        try {
                            t.get()
                        } catch (_: Exception) {
                        }
                    }
                    pool.shutdown()
                    try {
                        cm.unregisterNetworkCallback(zelf)
                    } catch (_: Exception) {
                    }
                    meld(HashMap(uit))
                }.start()
            }

            override fun onUnavailable() {
                try {
                    cm.unregisterNetworkCallback(this)
                } catch (_: Exception) {
                }
                meld(mapOf("fout" to "geen-mobiel"))
            }
        }
        try {
            cm.requestNetwork(vraag, terug, 10_000)
        } catch (e: Exception) {
            meld(mapOf("fout" to (e.message ?: "requestNetwork")))
        }
    }

    private fun probeer(network: Network, doel: String, pin: String): String {
        return try {
            val c = network.openConnection(URL(doel)) as HttpURLConnection
            c.connectTimeout = 10_000
            c.readTimeout = 10_000
            c.instanceFollowRedirects = false
            c.useCaches = false
            if (c is HttpsURLConnection) {
                val ctx = SSLContext.getInstance("TLS")
                ctx.init(null, arrayOf(PinVertrouwen(pin)), null)
                c.sslSocketFactory = ctx.socketFactory
                c.setHostnameVerifier { _, _ -> true }
            }
            val s = c.responseCode
            c.disconnect()
            if (s == 200) "antwoordt" else "status:$s"
        } catch (e: javax.net.ssl.SSLException) {
            if (oorzaakIsPin(e)) "ander-certificaat" else "geen"
        } catch (_: Exception) {
            "geen"
        }
    }

    private fun oorzaakIsPin(e: Throwable): Boolean {
        var x: Throwable? = e
        while (x != null) {
            if (x is CertificateException) return true
            x = x.cause
        }
        return false
    }

    /** Alleen het certificaat met precies deze vingerafdruk (sha256 van het DER), zoals `certificaat.dart`. */
    private class PinVertrouwen(private val pin: String) : X509TrustManager {
        override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {
            throw CertificateException("geen client-certificaten")
        }

        override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
            val p = MessageDigest.getInstance("SHA-256").digest(chain[0].encoded)
                .joinToString("") { "%02x".format(it) }
            if (pin.isEmpty() || p != pin) throw CertificateException("pin klopt niet")
        }

        override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
    }
}
