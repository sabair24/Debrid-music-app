package com.debridmusic.app

import android.app.Application
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class DebridMusicApp : Application() {
    override fun onCreate() {
        // Install the crash reporter as early as possible so even a failure during
        // Hilt initialization (in super.onCreate) is captured and shown.
        CrashReporter.install(this)
        super.onCreate()
    }
}
