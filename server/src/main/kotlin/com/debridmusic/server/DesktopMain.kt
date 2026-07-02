package com.debridmusic.server

import com.debridmusic.server.api.configureServer
import com.debridmusic.server.cast.CastManager
import com.debridmusic.server.cast.UpnpCast
import com.debridmusic.server.index.IndexStore
import com.debridmusic.server.scan.FileWatcher
import com.debridmusic.server.scan.LibraryScanner
import com.debridmusic.server.service.ArtworkService
import com.debridmusic.server.service.IngestService
import com.debridmusic.server.util.NetworkInfo
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import org.slf4j.LoggerFactory
import java.awt.*
import java.awt.image.BufferedImage
import java.io.File
import java.net.URI
import javax.swing.JFileChooser
import javax.swing.JOptionPane
import javax.swing.UIManager
import kotlin.system.exitProcess

/**
 * Desktop entry point for the packaged Windows app. Runs the same Ktor music
 * server, but self-configures (music folder + writable data dir), lives in the
 * system tray, and opens the web UI in the browser. Falls back to the headless
 * [main] behaviour when there's no display (servers/CI).
 */
object DesktopMain {
    private val log = LoggerFactory.getLogger("DebridMusicDesktop")
    private const val DEFAULT_MUSIC = "D:\\Flac music 2024"

    @JvmStatic
    fun main(args: Array<String>) {
        if (GraphicsEnvironment.isHeadless()) { runHeadlessServer(args); return } // no display → headless server

        val dataDir = ServerConfig.desktopDataDir()
        val port = (System.getenv("PORT") ?: "4533").toIntOrNull() ?: 4533
        val roots = resolveMusicRoots(dataDir) ?: run {
            JOptionPane.showMessageDialog(null, "No music folder selected. Exiting.")
            return
        }
        val token = ServerConfig.loadOrCreateToken(dataDir, System.getenv("AUTH_TOKEN"))
        val config = ServerConfig(
            musicRoots = roots, bindAddress = "0.0.0.0", port = port, authToken = token,
            username = "music", password = token, dataDir = dataDir,
        )

        val store = IndexStore(config.indexFile)
        val scanner = LibraryScanner(config.musicRoots, store)
        val artwork = ArtworkService(config.musicRoots, store)
        val ingest = IngestService(config.musicRoots, scanner, store)
        val cast = CastManager(store, UpnpCast(), lanBaseUrlFor = { host -> NetworkInfo.lanBaseUrlFor(host, port) }, token = token)

        log.info("Indexing {}…", roots.joinToString { it.absolutePath })
        scanner.scan()
        FileWatcher(config.musicRoots, onChange = { scanner.scan() }).start()

        val engine = embeddedServer(Netty, port = port, host = "0.0.0.0") {
            configureServer(config, store, artwork, ingest, cast)
        }.start(wait = false)

        val localUrl = "http://localhost:$port/?token=$token"
        val lanUrl = "${NetworkInfo.lanBaseUrl(port)}/?token=$token"
        installTray(config, store, localUrl, lanUrl, token, engine)
        openBrowser(localUrl)
        log.info("DebridMusic running. Local: {}  LAN: {}", localUrl, lanUrl)
    }

    /** env MUSIC_ROOTS → saved file → default D:\Flac music 2024 → folder picker. */
    private fun resolveMusicRoots(dataDir: File): List<File>? {
        System.getenv("MUSIC_ROOTS")?.takeIf { it.isNotBlank() }?.let { return parseRoots(it) }
        val saved = File(dataDir, "music_roots.txt")
        saved.takeIf { it.isFile }?.readText()?.trim()?.takeIf { it.isNotEmpty() }
            ?.let { return parseRoots(it) }
        File(DEFAULT_MUSIC).takeIf { it.isDirectory }?.let {
            saved.writeText(it.absolutePath); return listOf(it)
        }
        return pickFolder(dataDir)
    }

    private fun parseRoots(s: String): List<File> =
        s.split(File.pathSeparatorChar, ',').map { it.trim() }.filter { it.isNotEmpty() }.map { File(it) }

    private fun pickFolder(dataDir: File): List<File>? {
        runCatching { UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName()) }
        val chooser = JFileChooser().apply {
            dialogTitle = "Choose your music folder"
            fileSelectionMode = JFileChooser.DIRECTORIES_ONLY
        }
        if (chooser.showOpenDialog(null) != JFileChooser.APPROVE_OPTION) return null
        val dir = chooser.selectedFile ?: return null
        File(dataDir, "music_roots.txt").writeText(dir.absolutePath)
        return listOf(dir)
    }

    private fun installTray(
        config: ServerConfig, store: IndexStore,
        localUrl: String, lanUrl: String, token: String, engine: ApplicationEngine,
    ) {
        if (!SystemTray.isSupported()) return
        val tray = SystemTray.getSystemTray()
        val popup = PopupMenu()

        fun item(label: String, action: () -> Unit) = MenuItem(label).apply { addActionListener { action() } }

        popup.add(item("Open DebridMusic") { openBrowser(localUrl) })
        popup.add(item("Copy access token") { copyToClipboard(token) })
        popup.add(item("Copy LAN link (phone / iPad)") { copyToClipboard(lanUrl) })
        popup.addSeparator()
        popup.add(item("Change music folder…") {
            pickFolder(config.dataDir)?.let {
                JOptionPane.showMessageDialog(null, "Saved. Restart DebridMusic to index:\n${it.first().absolutePath}")
            }
        })
        popup.add(item("Open data folder") { openFolder(config.dataDir) })
        popup.addSeparator()
        popup.add(item("Quit") { runCatching { engine.stop(500, 1500) }; tray.remove(tray.trayIcons.firstOrNull()); exitProcess(0) })

        val icon = TrayIcon(trayImage(), "DebridMusic — ${store.trackCount()} tracks", popup).apply {
            isImageAutoSize = true
            addActionListener { openBrowser(localUrl) } // double-click opens the app
        }
        runCatching { tray.add(icon) }
        runCatching {
            icon.displayMessage(
                "DebridMusic is running",
                "${store.trackCount()} tracks · open from the tray. Phone/iPad: $lanUrl",
                TrayIcon.MessageType.INFO,
            )
        }
    }

    private fun trayImage(): Image {
        val size = 16
        val img = BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB)
        val g = img.createGraphics()
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
        g.paint = GradientPaint(0f, 0f, Color(0x7c5cff), size.toFloat(), size.toFloat(), Color(0x00d4c8))
        g.fillRoundRect(0, 0, size, size, 6, 6)
        g.color = Color.WHITE
        g.fillOval(4, 9, 5, 5)                 // note head
        g.fillRect(8, 3, 2, 8)                 // stem
        g.dispose()
        return img
    }

    private fun openBrowser(url: String) = runCatching {
        if (Desktop.isDesktopSupported() && Desktop.getDesktop().isSupported(Desktop.Action.BROWSE))
            Desktop.getDesktop().browse(URI(url))
    }

    private fun openFolder(dir: File) = runCatching {
        if (Desktop.isDesktopSupported()) Desktop.getDesktop().open(dir)
    }

    private fun copyToClipboard(text: String) = runCatching {
        Toolkit.getDefaultToolkit().systemClipboard.setContents(
            java.awt.datatransfer.StringSelection(text), null
        )
    }
}
