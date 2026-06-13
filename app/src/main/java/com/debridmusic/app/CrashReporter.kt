package com.debridmusic.app

import android.app.Application
import android.content.Intent
import android.os.Process
import android.util.Log
import java.io.File
import kotlin.system.exitProcess

/**
 * Captures any uncaught exception, saves the stack trace to a file, and shows it
 * on screen via [CrashActivity] (which runs in a separate process so it survives
 * the crash). This turns "the app just closes" into a readable, shareable error —
 * essential for diagnosing crashes on a device we can't attach a debugger to.
 */
object CrashReporter {
    const val EXTRA_TRACE = "crash_trace"
    private const val CRASH_FILE = "last_crash.txt"

    fun crashFile(app: Application): File =
        File(app.getExternalFilesDir(null) ?: app.filesDir, CRASH_FILE)

    fun install(app: Application) {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            val text = buildString {
                append("Debrid Music — crash\n")
                append("Versie: ${BuildConfig.VERSION_NAME} (build ${BuildConfig.BUILD_NUMBER})\n")
                append("Thread: ${thread.name}\n\n")
                append(Log.getStackTraceString(throwable))
            }
            runCatching { crashFile(app).writeText(text) }
            runCatching {
                val intent = Intent(app, CrashActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                    putExtra(EXTRA_TRACE, text)
                }
                app.startActivity(intent)
            }
            // Best-effort: also let any previously installed handler run.
            runCatching { previous?.uncaughtException(thread, throwable) }
            Process.killProcess(Process.myPid())
            exitProcess(10)
        }
    }
}
