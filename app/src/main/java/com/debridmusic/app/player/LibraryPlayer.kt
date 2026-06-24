package com.debridmusic.app.player

import com.debridmusic.app.domain.model.Track
import com.debridmusic.app.torbox.TorBoxRepository
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Plays library tracks. "Online" (torrent-backed) tracks are re-resolved to fresh
 * TorBox stream URLs first (links expire), so they play just like local files.
 */
@Singleton
class LibraryPlayer @Inject constructor(
    private val torBoxRepository: TorBoxRepository,
    private val playerController: PlayerController,
) {
    suspend fun play(tracks: List<Track>, startIndex: Int = 0) {
        val resolved = coroutineScope {
            tracks.map { t ->
                async {
                    val hash = t.torrentHash
                    val file = t.torrentFileName
                    if (t.isOnline && hash != null && file != null) {
                        val url = runCatching { torBoxRepository.resolveOnlineTrack(hash, file) }.getOrNull()
                        if (url != null) t.copy(uri = url) else t
                    } else t
                }
            }.awaitAll()
        }
        playerController.playQueue(resolved, startIndex.coerceIn(0, (resolved.size - 1).coerceAtLeast(0)))
    }
}
