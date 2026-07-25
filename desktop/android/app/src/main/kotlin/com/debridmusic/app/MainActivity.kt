package com.debridmusic.app

import android.content.pm.PackageManager
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
                    else -> result.notImplemented()
                }
            }
    }
}
