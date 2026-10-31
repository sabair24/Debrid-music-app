package com.debridmusic.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationCompat
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * De Shield vindbaar houden terwijl hij slaapt, en hem wekken als er muziek naartoe gaat.
 *
 * **Waarom (Saber, 31-10-2026).** *"kunnen we ervoor zorgen dat de app de shield vindt ook al slaapt hij, zoals sonos
 * kan dit, en dan wekt hij de shield als ik er naar wil streamen"* — en: *"dat hij de app start en na het wekken muziek
 * begint te spelen"*.
 *
 * **Gemeten op de Shield, 31-10-2026** (13 uur in slaap, Doze diep, Android 11). Het netwerk van de Shield zelf blijft
 * aan: Cast, adb en Debrid Media (8123) antwoordden. Debrid Music (8124) niet: `dumpsys netpolicy` gaf voor deze app
 * `REJECT_ALL`, want hij stond als CACHED; Debrid Media stond op `fg svc` en kreeg `ALLOW_ALL`. Een voorgronddienst
 * houdt het netwerk van de app dus open in de slaap. Dat is wat deze dienst doet, en verder niets: de ontvanger zelf
 * blijft in Dart (lib/lan/cast_receiver.dart), net als de lijn naar de pc.
 *
 * Alleen op een televisie. Een gsm die altijd luistert, start muziek zodra iemand in huis een speaker kiest.
 */
class OntvangerDienst : Service() {

    companion object {
        private const val KANAAL = "ontvanger"
        private const val MELDING = 4712

        /** Is dit een televisie? Dezelfde vraag als in MainActivity ("isTv"). */
        fun isTv(context: Context): Boolean {
            val pm = context.packageManager
            return pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                pm.hasSystemFeature("android.hardware.type.television")
        }

        /** Start de dienst, op een televisie. Nooit een fout: zonder dienst is de Shield alleen wakker te vinden. */
        fun start(context: Context) {
            if (!isTv(context)) return
            try {
                val i = Intent(context, OntvangerDienst::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(i)
                else context.startService(i)
            } catch (e: Exception) {
                // Bijvoorbeeld een start vanaf de achtergrond die Android weigert; bij de volgende start van de app opnieuw.
            }
        }
    }

    private val hoofd = Handler(Looper.getMainLooper())
    @Volatile private var draait = false

    override fun onCreate() {
        super.onCreate()
        val melding = maakMelding()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(MELDING, melding, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(MELDING, melding)
        }
        draait = true
        zorgVoorEngine()
    }

    /**
     * De Flutter-engine moet draaien, anders luistert er niemand op 8124.
     *
     * Na een herstart van de Shield of een update van de app is er geen scherm en dus geen engine. Dan start deze
     * dienst hem zelf, zonder scherm — dezelfde weg die audio_service neemt als Android Auto de app opent. Opent
     * iemand daarna de app, dan neemt MainActivity (een AudioServiceActivity) precies die engine over.
     *
     * Gooit audio_service de engine weg (zijn dienst stopt terwijl er geen scherm is), dan na drie seconden een nieuwe:
     * zolang deze dienst draait, moet de Shield te vinden zijn.
     */
    private fun zorgVoorEngine() {
        try {
            val nieuw = FlutterEngineCache.getInstance().get(AudioServicePlugin.getFlutterEngineId()) == null
            val engine = AudioServicePlugin.getFlutterEngine(applicationContext)
            val boodschapper = engine.dartExecutor.binaryMessenger
            registreerWekker(applicationContext, boodschapper)
            // Zonder scherm registreert MainActivity niets, en dan antwoordt "isTv" niet: Dart zou denken dat dit
            // een gsm is en de ontvanger niet starten (lib/tv.dart). Komt het scherm later, dan zet MainActivity
            // zijn eigen, volledige versie van dit kanaal eroverheen.
            if (nieuw) registreerToestelZonderScherm(applicationContext, boodschapper)
            engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
                override fun onPreEngineRestart() {}
                override fun onEngineWillDestroy() {
                    hoofd.postDelayed({ if (draait) zorgVoorEngine() }, 3000)
                }
            })
        } catch (e: Exception) {
            // Geen engine: dan is de Shield pas te vinden als iemand de app opent, zoals vroeger.
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        draait = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun maakMelding(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm != null && nm.getNotificationChannel(KANAAL) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(KANAAL, "Muziek ontvangen", NotificationManager.IMPORTANCE_LOW).apply {
                        setShowBadge(false)
                    }
                )
            }
        }
        return NotificationCompat.Builder(this, KANAAL)
            .setContentTitle("DebridMusic")
            .setContentText("Klaar om muziek te ontvangen, ook als de Shield slaapt")
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }
}

/**
 * Start [OntvangerDienst] na een herstart van de Shield, en na een update van de app (die sluit het proces af).
 * Zonder dit is de Shield na een stroomonderbreking pas weer te vinden als iemand de app opent.
 */
class OntvangerStart : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> OntvangerDienst.start(context)
        }
    }
}

/**
 * Het scherm aanzetten en de app vooraan, voor muziek die binnenkomt terwijl de Shield slaapt.
 *
 * **Het scherm.** Een wekslot met ACQUIRE_CAUSES_WAKEUP: op Android 11 (de Shield) zet dat het toestel aan zoals de
 * aan-knop van de afstandsbediening, en de Shield zet daarna zelf via HDMI-CEC de tv aan. Verouderd, maar de opvolger
 * (`setTurnScreenOn` op een activiteit) kan pas als die activiteit al mag starten — en dat is het tweede punt.
 *
 * **De app vooraan.** Android laat een app op de achtergrond geen scherm openen, tenzij hij "weergeven over andere
 * apps" mag. Debrid Media op dezelfde Shield doet het zo sinds juli (via adb gegeven); hier hetzelfde. Zonder die
 * toestemming speelt de muziek wel, maar blijft het startscherm van de Shield staan.
 *
 * Met de startopdracht van de launcher en NEW_TASK: is de app er al, dan komt zijn taak naar voren in plaats van een
 * tweede venster op dezelfde engine.
 */
object Wekker {
    fun slaapt(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return !pm.isInteractive
    }

    fun magVoorgrond(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    @Suppress("DEPRECATION")
    fun wek(context: Context): Map<String, Any> {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val sliep = pm != null && !pm.isInteractive
        if (sliep) {
            try {
                pm!!.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                    "debridmusic:wekken"
                ).acquire(5_000)
            } catch (e: Exception) {
                // Niet kunnen wekken: dan speelt hij toch, en zet je de tv zelf aan.
            }
        }
        var vooraan = false
        try {
            val pkg = context.packageManager
            val start = pkg.getLeanbackLaunchIntentForPackage(context.packageName)
                ?: pkg.getLaunchIntentForPackage(context.packageName)
            if (start != null) {
                start.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                context.startActivity(start)
                vooraan = true
            }
        } catch (e: Exception) {
            // Zie hierboven: de muziek gaat door, alleen het scherm blijft waar het was.
        }
        return mapOf(
            "sliep" to sliep,
            "wakker" to (pm?.isInteractive ?: true),
            "vooraan" to vooraan,
            "magVoorgrond" to magVoorgrond(context),
        )
    }
}

/** Het kanaal voor lib/wekker.dart. Zowel vanuit MainActivity als vanuit [OntvangerDienst] (zonder scherm). */
fun registreerWekker(context: Context, boodschapper: BinaryMessenger) {
    val app = context.applicationContext
    MethodChannel(boodschapper, "debridmusic/wekker").setMethodCallHandler { call, result ->
        when (call.method) {
            "slaapt" -> result.success(Wekker.slaapt(app))
            "magVoorgrond" -> result.success(Wekker.magVoorgrond(app))
            "wek" -> result.success(Wekker.wek(app))
            else -> result.notImplemented()
        }
    }
}

/**
 * "debridmusic/device" voor een engine die [OntvangerDienst] zonder scherm startte: alleen wat de app bij het starten
 * vraagt (`isTv`, `deviceName`). Dezelfde antwoorden als in MainActivity; die zet zijn eigen versie erover zodra het
 * scherm er is.
 */
private fun registreerToestelZonderScherm(context: Context, boodschapper: BinaryMessenger) {
    val app = context.applicationContext
    MethodChannel(boodschapper, "debridmusic/device").setMethodCallHandler { call, result ->
        when (call.method) {
            "isTv" -> result.success(OntvangerDienst.isTv(app))
            "deviceName" -> {
                // Zoals MainActivity.deviceName(): eerst de naam uit de instellingen ("Tv in woonkamer"), anders
                // merk en model. Een andere naam hier zou de zone na elke herstart van de Shield hernoemen.
                val gekozen = try {
                    Settings.Global.getString(app.contentResolver, Settings.Global.DEVICE_NAME)
                } catch (e: Exception) {
                    null
                }
                val model = Build.MODEL?.trim().orEmpty()
                val merk = Build.MANUFACTURER?.trim().orEmpty()
                result.success(
                    when {
                        !gekozen.isNullOrBlank() -> gekozen.trim()
                        model.isEmpty() -> merk.ifEmpty { "Android-toestel" }
                        merk.isEmpty() || model.startsWith(merk, ignoreCase = true) -> model
                        else -> "$merk $model"
                    }
                )
            }
            else -> result.notImplemented()
        }
    }
}
