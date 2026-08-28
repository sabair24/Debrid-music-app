package com.debridmusic.app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
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
                    "netsoort" -> result.success(netsoort())
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
