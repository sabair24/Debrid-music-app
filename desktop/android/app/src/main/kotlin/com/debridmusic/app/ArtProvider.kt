package com.debridmusic.app

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File

/**
 * Hands the sleeve of the playing track to whoever is drawing it.
 *
 * Android Auto's full playback screen does not use the bitmap in the session metadata. It takes the
 * artwork URI and loads it in ITS OWN process — and a `file://` path under this app's private
 * folder is unreadable there. That is the exact split we saw on a dashboard: the small media card
 * on the navigation screen, which does use the bitmap, had the cover, and the big "Wordt nu
 * afgespeeld" screen had a grey square.
 *
 * A `content://` URI is the one form every media client can read. Deliberately a provider of its
 * own rather than an `androidx` FileProvider: that cannot be exported, so every consumer would need
 * an explicit `grantUriPermission` — and there is no reliable list of the package names a head
 * unit, an assistant or a watch face will come from.
 *
 * The price of exporting is bounded on purpose. This serves ONE directory, read-only, and that
 * directory holds nothing but album covers the app has just published — no settings, no tokens, no
 * music. Names resolve against the directory's canonical path, so no `..` can walk out of it.
 */
class ArtProvider : ContentProvider() {

    override fun onCreate(): Boolean = true

    /** Where [now_playing.dart] writes the covers. Kept in one place; [MainActivity] asks for it. */
    companion object {
        fun artDir(context: Context): File = File(context.filesDir, "DebridMusic/nowplaying")

        fun authority(context: Context): String = "${context.packageName}.art"
    }

    /**
     * The file a URI points at, or null when it points anywhere else.
     *
     * The canonical-path check is the whole security of this class: a last segment of
     * `..%2F..%2Fsettings.json` would otherwise resolve to a file holding passwords.
     */
    private fun fileFor(uri: Uri): File? {
        val ctx = context ?: return null
        val name = uri.lastPathSegment ?: return null
        val dir = artDir(ctx)
        val file = File(dir, name)
        return try {
            val inside = file.canonicalPath.startsWith(dir.canonicalPath + File.separator)
            if (inside && file.isFile) file else null
        } catch (e: Exception) {
            null
        }
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        // Read-only whatever is asked for. A client that wants to write gets a file it cannot open
        // rather than a file it can damage.
        val file = fileFor(uri) ?: return null
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String = "image/jpeg"

    /**
     * Name and size. Image loaders ask for these before they open anything, and a provider that
     * answers null to the query is one they give up on before reaching [openFile].
     */
    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? {
        val file = fileFor(uri) ?: return null
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(columns, 1)
        val row = cursor.newRow()
        for (column in columns) {
            when (column) {
                OpenableColumns.DISPLAY_NAME -> row.add(file.name)
                OpenableColumns.SIZE -> row.add(file.length())
                else -> row.add(null)
            }
        }
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0
}
