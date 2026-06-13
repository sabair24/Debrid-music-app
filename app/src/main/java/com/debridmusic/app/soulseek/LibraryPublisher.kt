package com.debridmusic.app.soulseek

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Moves a finished download into the public Music library via MediaStore so it
 * persists and is picked up by the device/library scanner. Returns a playable
 * URI (content:// on Android 10+, file path on older versions).
 */
@Singleton
class LibraryPublisher @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    suspend fun publish(
        tempPath: String,
        originalFileName: String,
        title: String,
        artist: String,
        album: String,
    ): String =
        withContext(Dispatchers.IO) {
            val src = File(tempPath)
            if (!src.exists() || src.length() == 0L) error("Gedownload bestand ontbreekt")
            val ext = originalFileName.substringAfterLast('.', "mp3")
            val fileName = sanitize(if (title.isNotBlank()) "$title.$ext" else originalFileName)
            val mime = mimeFor(fileName)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                publishViaMediaStore(src, fileName, title.ifBlank { fileName.substringBeforeLast('.') }, artist, album, mime)
            } else {
                publishViaFile(src, fileName)
            }
        }

    private fun publishViaMediaStore(
        src: File, fileName: String, title: String, artist: String, album: String, mime: String,
    ): String {
        val resolver = context.contentResolver
        val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Audio.Media.TITLE, title)
            if (artist.isNotBlank()) put(MediaStore.Audio.Media.ARTIST, artist)
            if (album.isNotBlank()) put(MediaStore.Audio.Media.ALBUM, album)
            put(MediaStore.Audio.Media.MIME_TYPE, mime)
            put(MediaStore.Audio.Media.IS_MUSIC, 1)
            put(MediaStore.Audio.Media.RELATIVE_PATH, "Music/DebridMusic")
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: error("Kon niet opslaan in bibliotheek")
        resolver.openOutputStream(uri)?.use { out -> src.inputStream().use { it.copyTo(out) } }
            ?: error("Kon bestand niet wegschrijven")
        values.clear()
        values.put(MediaStore.Audio.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        src.delete()
        return uri.toString()
    }

    // Android 9 and below: copy into the public Music dir and register with MediaStore.
    private fun publishViaFile(src: File, fileName: String): String {
        @Suppress("DEPRECATION")
        val musicDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), "DebridMusic")
        musicDir.mkdirs()
        val dest = File(musicDir, fileName)
        src.copyTo(dest, overwrite = true)
        src.delete()
        android.media.MediaScannerConnection.scanFile(context, arrayOf(dest.absolutePath), null, null)
        return Uri_fromFile(dest)
    }

    private fun Uri_fromFile(f: File): String = "file://${f.absolutePath}"

    private fun sanitize(name: String): String {
        val cleaned = name.replace(Regex("[^a-zA-Z0-9 ._()\\-\\[\\]]"), "_").trim()
        return cleaned.ifBlank { "track_${System.currentTimeMillis()}.mp3" }
    }

    private fun mimeFor(name: String): String = when (name.substringAfterLast('.').lowercase()) {
        "flac" -> "audio/flac"
        "mp3" -> "audio/mpeg"
        "m4a", "aac", "alac" -> "audio/mp4"
        "ogg", "oga" -> "audio/ogg"
        "opus" -> "audio/opus"
        "wav" -> "audio/x-wav"
        "ape" -> "audio/x-ape"
        else -> "audio/*"
    }
}
