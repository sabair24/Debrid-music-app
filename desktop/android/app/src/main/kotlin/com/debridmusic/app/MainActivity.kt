package com.debridmusic.app

import com.ryanheise.audioservice.AudioServiceActivity

/**
 * AudioServiceActivity, not FlutterActivity.
 *
 * `audio_service` needs the activity it is hosted in to be this one — it is what keeps the Flutter
 * engine alive in a cache the background service can reach. With a plain FlutterActivity the
 * notification and the lockscreen appear once and then talk to an engine that is no longer there,
 * which reads as "the buttons stopped working" rather than as a wiring mistake.
 */
class MainActivity : AudioServiceActivity()
