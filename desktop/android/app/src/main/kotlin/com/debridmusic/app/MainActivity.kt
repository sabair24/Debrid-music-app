package com.debridmusic.app

import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.io.File
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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

    /**
     * A `content://` URI for a cover this app has written, or null if [path] is not one.
     *
     * The check is on the canonical path, not on the string: this is what decides whether another
     * process gets to open a file, and `…/nowplaying/../../settings.json` is a string that starts
     * with the right prefix and is not in the right folder.
     */
    private fun artContentUri(path: String?): String? {
        if (path.isNullOrBlank()) return null
        return try {
            val dir = ArtProvider.artDir(applicationContext)
            val file = File(path)
            if (!file.canonicalPath.startsWith(dir.canonicalPath + File.separator)) return null
            if (!file.isFile) return null
            Uri.Builder()
                .scheme("content")
                .authority(ArtProvider.authority(applicationContext))
                .appendPath(file.name)
                .build()
                .toString()
        } catch (e: Exception) {
            null
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
                    // The cover, as something another app is allowed to open. See [ArtProvider].
                    //
                    // Null for anything outside the one folder that provider serves — and Dart
                    // then keeps the file:// URI it already had. So if the app's data layout ever
                    // moves, this degrades to what it did before rather than breaking silently.
                    "artContentUri" -> result.success(artContentUri(call.argument<String>("path")))
                    else -> result.notImplemented()
                }
            }
    }
}
