package com.debridmusic.server.cast

import com.debridmusic.server.index.IndexStore
import org.slf4j.LoggerFactory

/**
 * Tracks the currently-casting device + queue and drives it through [UpnpCast].
 * One active session at a time (a single-user home setup). The stream URL handed
 * to the renderer uses the machine's LAN address so the speaker can fetch it.
 */
class CastManager(
    private val store: IndexStore,
    private val cast: UpnpCast,
    /** Given the target speaker's host, returns a base URL that speaker can reach. */
    private val lanBaseUrlFor: (targetHost: String) -> String,
    private val token: String,
) {
    private val log = LoggerFactory.getLogger(CastManager::class.java)

    @Volatile private var cache: Map<String, Renderer> = emptyMap()
    private data class Session(val deviceId: String, val queue: List<String>, var index: Int)
    @Volatile private var session: Session? = null

    fun devices(): List<Renderer> {
        cache = cast.discover().associateBy { it.id }
        return cache.values.toList()
    }

    private fun renderer(id: String): Renderer =
        cache[id] ?: cast.discover().associateBy { it.id }.also { cache = it }[id]
        ?: throw IllegalArgumentException("Speaker not found on the network")

    fun play(deviceId: String, queue: List<String>, index: Int) {
        val r = renderer(deviceId)
        val q = queue.ifEmpty { session?.queue ?: emptyList() }
        session = Session(deviceId, q, index.coerceIn(0, (q.size - 1).coerceAtLeast(0)))
        playCurrent(r)
    }

    private fun playCurrent(r: Renderer) {
        val s = session ?: return
        val id = s.queue.getOrNull(s.index) ?: return
        val t = store.track(id) ?: run { log.warn("cast: track {} missing", id); return }
        val url = "${lanBaseUrlFor(r.host)}/stream/$id?token=$token"
        cast.playUrl(r, url, t.title, t.artistName, t.albumTitle, t.mime ?: "audio/mpeg")
        log.info("Casting '{}' to {}", t.title, r.name)
    }

    fun control(deviceId: String, action: String, value: Int?) {
        val r = renderer(deviceId)
        when (action.lowercase()) {
            "play" -> cast.play(r)
            "pause" -> cast.pause(r)
            "stop" -> { cast.stop(r); session = null }
            "next" -> session?.let { if (it.index < it.queue.lastIndex) { it.index++; playCurrent(r) } }
            "prev", "previous" -> session?.let { if (it.index > 0) { it.index--; playCurrent(r) } }
            "volume" -> cast.setVolume(r, value ?: 50)
            else -> throw IllegalArgumentException("Unknown action: $action")
        }
    }
}
