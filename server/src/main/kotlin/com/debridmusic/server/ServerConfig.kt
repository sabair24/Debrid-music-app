package com.debridmusic.server

import java.io.File
import java.security.SecureRandom

/**
 * Configuration is read from environment variables (with sensible defaults) so the
 * server runs with a single command on any PC. A `.env`-style properties file passed
 * as the first CLI arg is also merged in (keys = the same env var names).
 */
data class ServerConfig(
    val musicRoots: List<File>,
    val bindAddress: String,
    val port: Int,
    val authToken: String,
    val username: String,
    val password: String,
    val dataDir: File,
) {
    val thumbsDir: File get() = File(dataDir, "thumbs")
    val indexFile: File get() = File(dataDir, "index.db")

    companion object {
        const val VERSION = "0.1.0"

        fun load(args: Array<String>): ServerConfig {
            val fileProps = args.firstOrNull()?.let { path ->
                runCatching {
                    val p = java.util.Properties()
                    File(path).inputStream().use { p.load(it) }
                    p.entries.associate { (k, v) -> k.toString() to v.toString() }
                }.getOrDefault(emptyMap())
            } ?: emptyMap()

            fun value(key: String, default: String? = null): String? =
                System.getenv(key) ?: fileProps[key] ?: default

            val roots = (value("MUSIC_ROOTS") ?: "")
                .split(File.pathSeparatorChar, ',')
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .map { File(it) }
            require(roots.isNotEmpty()) {
                "MUSIC_ROOTS is required (one or more folder paths, comma- or ${File.pathSeparator}-separated)."
            }

            val dataDir = File(value("DATA_DIR", "./data")!!).absoluteFile
            dataDir.mkdirs()

            val token = loadOrCreateToken(dataDir, value("AUTH_TOKEN"))

            return ServerConfig(
                musicRoots = roots,
                bindAddress = value("BIND", "0.0.0.0")!!,
                port = value("PORT", "4533")!!.toInt(),
                authToken = token,
                username = value("USERNAME", "music")!!,
                password = value("PASSWORD", token)!!,
                dataDir = dataDir,
            )
        }

        /** Stable, per-machine token: honour an override, else reuse/persist one in [dataDir]. */
        fun loadOrCreateToken(dataDir: File, override: String? = null): String {
            dataDir.mkdirs()
            val tokenFile = File(dataDir, "token.txt")
            return override?.takeIf { it.isNotBlank() }
                ?: tokenFile.takeIf { it.isFile }?.readText()?.trim()?.takeIf { it.isNotBlank() }
                ?: randomToken().also { tokenFile.writeText(it) }
        }

        /** A user-writable data directory (the packaged app can't write under Program Files). */
        fun desktopDataDir(): File {
            val base = System.getenv("LOCALAPPDATA")?.let { File(it) }
                ?: System.getenv("XDG_DATA_HOME")?.let { File(it) }
                ?: File(System.getProperty("user.home"))
            return File(base, "DebridMusic").apply { mkdirs() }
        }

        private fun randomToken(): String {
            val bytes = ByteArray(24)
            SecureRandom().nextBytes(bytes)
            return bytes.joinToString("") { "%02x".format(it) }
        }
    }
}
