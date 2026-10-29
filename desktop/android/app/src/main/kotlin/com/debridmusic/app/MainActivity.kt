package com.debridmusic.app

import android.Manifest
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.TrafficStats
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.os.StatFs
import android.provider.DocumentsContract
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * AudioServiceActivity, not FlutterActivity.
 *
 * `audio_service` needs the activity it is hosted in to be this one — it is what keeps the Flutter
 * engine alive in a cache the background service can reach. With a plain FlutterActivity the
 * notification and the lockscreen appear once and then talk to an engine that is no longer there,
 * which reads as "the buttons stopped working" rather than as a wiring mistake.
 */
class MainActivity : AudioServiceActivity() {

    companion object {
        /** Waar de netwerkwissels heen gaan (lib/netwerkwissel.dart), of null zolang Dart niet luistert. */
        @Volatile private var netwerkOor: EventChannel.EventSink? = null
        @Volatile private var netwerkGeregistreerd = false
        private val hoofd = Handler(Looper.getMainLooper())

        /** Per netwerk de laatst gemelde stand, zodat alleen een ECHTE wissel een melding wordt. */
        private val laatste = HashMap<String, String>()

        /**
         * Elke netwerkwissel naar Dart, zodat de app meteen een ander adres van de pc kiest.
         *
         * **Waarom.** Stap 4 van "verbinden zoals Roon ARC" (14-10-2026). Saber: "als ik het huis
         * verlaat … heb ik ineens geen internet meer". De app merkte een wissel pas als een verzoek
         * vastliep — een poll per vijftien seconden, met dertig seconden geduld per verzoek. Nu zegt
         * Android het zelf.
         *
         * **Eén keer per proces**, met de applicatiecontext: configureFlutterEngine draait bij elke
         * nieuwe Activity (MainActivity is een AudioServiceActivity), en Android weigert boven de
         * honderd callbacks per app. Twee callbacks: het standaardnetwerk (met Tailscale aan is dat
         * de VPN) en elk fysiek netwerk met internet (wifi of mobiel eronder).
         *
         * **Alleen echte wissels.** onCapabilitiesChanged vuurt ook bij elke verandering in
         * signaalsterkte; daarom wordt per netwerk alleen soort + gevalideerd + adressen vergeleken.
         */
        @Synchronized
        private fun registreerNetwerkwacht(context: Context) {
            if (netwerkGeregistreerd) return
            val cm = context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE)
                as? ConnectivityManager ?: return

            fun meld(soort: String, netwerk: Network?, caps: NetworkCapabilities?, lp: LinkProperties?) {
                val transport = when {
                    caps == null -> "onbekend"
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobiel"
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "kabel"
                    else -> "anders"
                }
                val gevalideerd = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) ?: false
                val adressen = lp?.linkAddresses?.joinToString(",") { it.address.hostAddress ?: "" } ?: ""
                val sleutel = soort.substringBefore('-') + "|" + (netwerk?.toString() ?: "")
                val stand = "$soort|$transport|$gevalideerd|$adressen"
                synchronized(laatste) {
                    if (laatste[sleutel] == stand) return
                    laatste[sleutel] = stand
                }
                val bericht = mapOf(
                    "soort" to soort,
                    "netwerk" to (netwerk?.toString() ?: ""),
                    "transport" to transport,
                    "gevalideerd" to gevalideerd,
                )
                hoofd.post { netwerkOor?.success(bericht) }
            }

            val standaard = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) =
                    meld("standaard-beschikbaar", network, cm.getNetworkCapabilities(network), cm.getLinkProperties(network))
                override fun onLost(network: Network) = meld("standaard-weg", network, null, null)
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) =
                    meld("standaard-eigenschappen", network, caps, cm.getLinkProperties(network))
                override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) =
                    meld("standaard-eigenschappen", network, cm.getNetworkCapabilities(network), lp)
            }
            val fysiek = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) =
                    meld("fysiek-beschikbaar", network, cm.getNetworkCapabilities(network), cm.getLinkProperties(network))
                override fun onLost(network: Network) = meld("fysiek-weg", network, null, null)
            }
            try {
                cm.registerDefaultNetworkCallback(standaard)
                // Zonder VPN: een NetworkRequest sluit VPN standaard uit, dus dit volgt wifi en mobiel.
                cm.registerNetworkCallback(
                    NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(),
                    fysiek,
                )
                netwerkGeregistreerd = true
            } catch (e: Exception) {
                // Zonder seintjes valt de app terug op wat er was: de poll van vijftien seconden.
            }
        }
    }

    /**
     * What to call this device in the PC's list of trusted devices.
     *
     * Dart cannot answer this: `Platform.localHostname` returns "localhost" on Android, so every
     * phone and every television arrived in that list under the same useless name — and picking
     * which one to revoke was guesswork.
     *
     * The name the owner set in Android's own settings comes first ("Saber's Phone" beats
     * "SM-G991B"). DEVICE_NAME is a plain string key, so reading it is safe on any API level; it
     * simply comes back null where the setting does not exist.
     */
    /**
     * Zit dit toestel op wifi of op mobiele data?
     *
     * Waarvoor: de app stuurt op mobiel een kleinere versie van je muziek van de pc naar hier. Zie
     * `lib/netsoort.dart` en `lib/lan/stroomstand.dart`.
     *
     * Een telefoon-hotspot meldt zichzelf als WIFI en is toch iemands databundel — vandaar dat
     * NOT_METERED meeweegt en niet alleen het soort verbinding. Android zelf gebruikt precies dat
     * vlaggetje om te beslissen of iets mag wachten tot je thuis bent.
     *
     * Bij twijfel "onbekend", nooit een gok. De Dart-kant laat onbekend expres naar de THUIS-stand
     * vallen: een mislukte meting mag je thuis nooit stilletjes je hi-res kosten.
     */
    private fun netsoort(): String {
        return try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return "onbekend"
            val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return "onbekend"
            when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobiel"
                !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) -> "mobiel"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "wifi"
                else -> "onbekend"
            }
        } catch (e: Exception) {
            "onbekend"
        }
    }

    /** Bytes (ontvangen + verzonden) van deze app per soort netwerk, of null als Android het niet zegt. */
    @Suppress("DEPRECATION")
    private fun verbruik(vanaf: Long, tot: Long): Map<String, Long>? {
        return try {
            val nsm = getSystemService(Context.NETWORK_STATS_SERVICE) as? NetworkStatsManager ?: return null
            val uid = Process.myUid()
            fun som(soort: Int): Long {
                var totaal = 0L
                val stats = nsm.queryDetailsForUid(soort, null, vanaf, tot, uid)
                val b = NetworkStats.Bucket()
                while (stats.hasNextBucket()) {
                    stats.getNextBucket(b)
                    totaal += b.rxBytes + b.txBytes
                }
                stats.close()
                return totaal
            }
            mapOf("mobiel" to som(ConnectivityManager.TYPE_MOBILE), "wifi" to som(ConnectivityManager.TYPE_WIFI))
        } catch (e: Exception) {
            null
        }
    }

    private fun deviceName(): String {
        try {
            val chosen = Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
            if (!chosen.isNullOrBlank()) return chosen.trim()
        } catch (e: Exception) {
            // A restricted profile can refuse the read. The model below is still an answer.
        }
        val model = Build.MODEL?.trim().orEmpty()
        val brand = Build.MANUFACTURER?.trim().orEmpty()
        return when {
            model.isEmpty() -> brand.ifEmpty { "Android-toestel" }
            // "NVIDIA SHIELD Android TV" already says who made it; "Samsung Samsung SM-G991B" does
            // not need saying twice.
            brand.isEmpty() || model.startsWith(brand, ignoreCase = true) -> model
            else -> "$brand $model"
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Is this a television?
        //
        // Asked of the system rather than guessed from the screen size. A tablet in landscape and
        // a TV report almost the same thing, and getting it wrong the other way is worse: overscan
        // margins and ten-foot type on a phone would look like a bug. The leanback feature is what
        // Android itself uses to decide, so it is what we ask.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "debridmusic/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTv" -> result.success(
                        packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                            packageManager.hasSystemFeature("android.hardware.type.television")
                    )
                    "deviceName" -> result.success(deviceName())
                    // Vrije ruimte, voor de vraag vóór "Op dit toestel" (lib/ui/op_toestel.dart, Saber 29-10-2026).
                    "vrijeRuimte" -> result.success(
                        try { StatFs(filesDir.path).availableBytes } catch (e: Exception) { -1L }
                    )
                    "netsoort" -> result.success(netsoort())
                    // Dataverbruik (lib/dataverbruik.dart): wat deze app sinds het opstarten van het toestel ontving en
                    // verstuurde, over elk netwerk.
                    "verkeer" -> result.success(
                        mapOf("rx" to TrafficStats.getUidRxBytes(Process.myUid()),
                            "tx" to TrafficStats.getUidTxBytes(Process.myUid()))
                    )
                    // En wat Android zelf telt voor deze app, mobiel en wifi apart, tussen twee tijdstippen: hetzelfde
                    // getal als in Instellingen › Verbindingen › Dataverbruik. Eigen verbruik vragen mag zonder recht.
                    "verbruik" -> result.success(
                        verbruik(call.argument<Number>("vanaf")?.toLong() ?: 0L,
                            call.argument<Number>("tot")?.toLong() ?: System.currentTimeMillis())
                    )
                    else -> result.notImplemented()
                }
            }

        // Wil het systeem dicht glas? Batterijbesparing, of Samsungs "Transparantie en vervaging
        // verminderen" (Toegankelijkheid). Zie lib/systeem_glas.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "debridmusic/systeem")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dichtGlas" -> {
                        val stroom = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val minder = listOf("accessibility_reduce_transparency", "reduce_transparency").any { sleutel ->
                            try {
                                Settings.System.getInt(contentResolver, sleutel, 0) == 1 ||
                                    Settings.Secure.getInt(contentResolver, sleutel, 0) == 1
                            } catch (e: Exception) {
                                false
                            }
                        }
                        result.success(stroom.isPowerSaveMode || minder)
                    }
                    else -> result.notImplemented()
                }
            }

        // Netwerkwissels, zie registreerNetwerkwacht. Het oor wordt per engine gezet; de callbacks zelf
        // maar één keer per proces.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "debridmusic/netwerk")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    netwerkOor = events
                    registreerNetwerkwacht(applicationContext)
                }

                override fun onCancel(arguments: Any?) {
                    netwerkOor = null
                }
            })

        // "Test buitenverbinding": een paar verzoeken over mobiele data, ook met wifi aan. Zie
        // Buitenproef.kt en lib/buitenproef.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "debridmusic/buiten")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "proef" -> {
                        val doelen = call.argument<List<String>>("doelen") ?: emptyList()
                        val pin = call.argument<String>("pin") ?: ""
                        Buitenproef.proef(applicationContext, doelen, pin) { uit -> result.success(uit) }
                    }
                    else -> result.notImplemented()
                }
            }

        // De openbare map voor wat je op dit toestel bewaart (Saber, 28-10-2026): Muziek/Debrid Music, met de
        // indeling van de pc. Zie lib/toestelmap.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "debridmusic/bestanden")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "mag" -> result.success(magAlleBestanden())
                    "vraag" -> {
                        vraagAlleBestanden()
                        result.success(null)
                    }
                    "muziekMap" -> result.success(
                        File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), "Debrid Music")
                            .absolutePath
                    )
                    "scan" -> {
                        // Andere apps (en Bestanden) zien een nieuw of weggehaald bestand pas na een mediascan.
                        val pad = call.argument<String>("pad")
                        if (!pad.isNullOrBlank()) MediaScannerConnection.scanFile(this, arrayOf(pad), null, null)
                        result.success(null)
                    }
                    "open" -> result.success(openMap(call.argument<String>("pad") ?: ""))
                    else -> result.notImplemented()
                }
            }

        // Bijwerken vanuit de app. Zie lib/updater.dart voor de kant die de APK binnenhaalt.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "debridmusic/updater")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "magInstalleren" -> result.success(magInstalleren())
                    "vraagToestemming" -> {
                        vraagToestemming()
                        result.success(null)
                    }
                    "installeer" -> {
                        val pad = call.argument<String>("pad")
                        if (pad.isNullOrBlank()) {
                            result.error("geen-pad", "Geen pad naar de APK meegegeven.", null)
                        } else {
                            try {
                                installeer(File(pad))
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("installeren-mislukt", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Mag deze app een andere app installeren?
     *
     * Sinds Android 8 is dat een recht PER APP en niet meer één schakelaar voor het hele toestel.
     * Zonder dit vooraf te vragen opent het installatiescherm en sluit het meteen weer, zonder een
     * woord — wat leest als een update die stuk is in plaats van als een ontbrekend vinkje.
     */
    /** Mag de app overal in de gedeelde opslag schrijven ("Toegang tot alle bestanden" vanaf Android 11)? */
    private fun magAlleBestanden(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }

    /**
     * Het scherm waar je "Toegang tot alle bestanden" voor deze app aanzet. De app zet het nooit zelf aan; jij
     * doet het daar, één keer. Onder Android 11 de gewone vraag om schrijfrechten.
     */
    private fun vraagAlleBestanden() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                        .setData(Uri.parse("package:$packageName"))
                )
            } catch (e: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else {
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE, Manifest.permission.READ_EXTERNAL_STORAGE), 4711
            )
        }
    }

    /**
     * De map in een bestandsbeheerder openen. Eerst Mijn bestanden van Samsung (dat opent een pad rechtstreeks;
     * de S26), anders de map via de Bestanden-app van Android.
     */
    private fun openMap(pad: String): Boolean {
        try {
            startActivity(Intent("samsung.myfiles.intent.action.LAUNCH_MY_FILES").apply {
                setPackage("com.sec.android.app.myfiles")
                putExtra("samsung.myfiles.intent.extra.START_PATH", pad)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
            return true
        } catch (e: Exception) {
            // Geen Samsung: hieronder verder.
        }
        val wortel = Environment.getExternalStorageDirectory().absolutePath
        val rel = pad.removePrefix(wortel).trimStart('/')
        val uri = DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", "primary:$rel")
        return try {
            startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, DocumentsContract.Document.MIME_TYPE_DIR)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            })
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun magInstalleren(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            // Daaronder is het één systeeminstelling die standaard aan kan staan; er valt hier niets
            // te vragen. minSdk is 24, dus dit pad bestaat echt.
            true
        }

    private fun vraagToestemming() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        startActivity(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                .setData(Uri.parse("package:$packageName"))
        )
    }

    /**
     * Geeft de APK aan het installatiescherm van het toestel.
     *
     * **De valkuil, en waarom hier een TWEEDE provider staat naast HoesProvider.** Een `file://`-URI
     * mag sinds Android 7 niet meer buiten de app: dat gooit `FileUriExposedException`. Er moet dus
     * een `content://` overheen, en daarvoor is `FileProvider` gemaakt.
     *
     * HoesProvider kan dat hier niet doen. Die is `exported="true"` omdat Android Auto in een ANDER
     * proces zijn hoesjes ophaalt, en juist daarom kan hij geen androidx-FileProvider zijn — die
     * weigert geëxporteerd te worden en laat de app bij élke start crashen. Zie het commentaar in
     * AndroidManifest.xml.
     *
     * Het installatiescherm werkt precies andersom: die provider moet NIET geëxporteerd zijn, en
     * krijgt eenmalig leesrecht mee via FLAG_GRANT_READ_URI_PERMISSION. Twee providers dus, met
     * tegengestelde instellingen, om twee verschillende redenen. Ze verwisselen is een app die niet
     * meer start.
     */
    private fun installeer(apk: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.apk", apk)
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}
