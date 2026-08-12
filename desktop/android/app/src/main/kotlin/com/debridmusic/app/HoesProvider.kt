package com.debridmusic.app

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * De albumhoezen die Android Auto te zien krijgt.
 *
 * **Waarom dit bestaat, en waarom het niet de FileProvider van androidx is.** Auto draait in een
 * ánder proces (Google's Gearhead) en laadt de `artUri` van een bladeritem zélf. Een `file:`-pad in
 * onze privémap kan hij niet openen — dat gaf grijze vlakken waar de platenkast hoort te staan. Het
 * speelscherm werkt wél met een `file:`-URI, want dáár laadt `audio_service` de bytes binnen ons
 * eigen proces en geeft er een Bitmap van door. Twee verschillende wegen, en die tweede was er niet.
 *
 * De voor de hand liggende oplossing — `androidx.core.content.FileProvider` met `exported="true"` —
 * bestaat niet. Die weigert het, en niet met een waarschuwing maar met een crash van het hele
 * proces bij élke start van de app:
 *
 * ```
 * java.lang.SecurityException: Provider must not be exported
 *     at androidx.core.content.FileProvider.attachInfo
 * ```
 *
 * Het bouwen was groen, de toetsen waren groen, de APK installeerde. Pas de telefoon zei het.
 * Vandaar deze: een eigen provider kent die controle niet.
 *
 * **Wat hij wél en niet deelt.** Precies één map, alleen lezen, en alleen bestandsnamen die deze
 * app zelf gemaakt heeft: zestien hexcijfers en `.jpg`, de md5 van de hoes. Zie `auto_hoezen.dart`
 * voor de kant die ze schrijft. Alles daarbuiten — een andere map, een `..`, een naam die er niet
 * zo uitziet — krijgt een [FileNotFoundException] en niet een bestand.
 *
 * Dat hij geëxporteerd is betekent dat elke app op dit toestel een albumhoes kán opvragen, mits hij
 * de md5 van de bytes al kent. Dat is de prijs, en hij is bewust: het alternatief is per URI
 * toestemming geven aan Gearhead op het moment dat Auto bladert, en dat moet gebeuren in het proces
 * van de `MediaBrowserService` — die van `audio_service` is, niet van ons.
 */
class HoesProvider : ContentProvider() {

    companion object {
        /** Moet gelijk blijven aan wat `auto_hoezen.dart` schrijft. */
        private val NAAM = Regex("^[0-9a-f]{16}\\.jpg$")

        /** Moet gelijk blijven aan `appSubdir('autohoezen')` in paths.dart. */
        private const val MAP = "DebridMusic/autohoezen"

        private const val TYPE = "image/jpeg"
    }

    override fun onCreate(): Boolean = true

    /**
     * Het bestand achter een URI, of null als de URI er niet een van ons is.
     *
     * De naamcontrole doet het echte werk: een `..` of een schuine streep haalt [Regex] nooit, dus
     * er valt niet uit de map te ontsnappen. De vergelijking van het volledige pad daarna is de
     * riem naast de bretel — als de regex ooit versoepelt, houdt die het nog steeds tegen.
     */
    private fun bestandVoor(uri: Uri): File? {
        val naam = uri.lastPathSegment ?: return null
        if (!NAAM.matches(naam)) return null
        val ctx = context ?: return null
        val map = File(ctx.filesDir, MAP)
        val f = File(map, naam)
        if (f.canonicalPath != File(map.canonicalPath, naam).path) return null
        return if (f.isFile) f else null
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        // Alleen lezen. "rw" zou van deze provider een schrijfbare map voor elke app op het toestel
        // maken, en daar is geen enkele reden voor.
        if (mode != "r") throw FileNotFoundException("alleen lezen: $uri")
        val f = bestandVoor(uri) ?: throw FileNotFoundException("geen hoes: $uri")
        return ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String? = if (bestandVoor(uri) != null) TYPE else null

    /**
     * Naam en grootte, want een plaatjeslader vraagt daar vaak eerst naar.
     *
     * Zonder dit geeft de provider null terug en concluderen sommige laders dat de URI niet bestaat
     * — zónder ooit [openFile] te proberen. Dat is precies het soort stilte dat een grijze tegel
     * oplevert zonder ergens een fout te melden.
     */
    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? {
        val f = bestandVoor(uri) ?: return null
        val kolommen = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val c = MatrixCursor(kolommen)
        c.addRow(kolommen.map {
            when (it) {
                OpenableColumns.DISPLAY_NAME -> f.name
                OpenableColumns.SIZE -> f.length()
                else -> null
            }
        }.toTypedArray())
        return c
    }

    // Deze provider deelt hoezen. Hij neemt niets aan.
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
