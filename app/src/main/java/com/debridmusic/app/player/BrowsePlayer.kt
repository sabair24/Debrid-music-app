package com.debridmusic.app.player

import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.domain.model.Track
import com.debridmusic.app.metadata.StreamArtworkResolver
import com.debridmusic.app.torbox.StreamState
import com.debridmusic.app.torbox.TorBoxRepository
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Bridges browse metadata (a song or album the user picked) to actual playback:
 * searches torrent sources (cached-first), resolves the best one via TorBox into a
 * track queue, and plays it. For a song it starts on the best-matching track.
 */
@Singleton
class BrowsePlayer @Inject constructor(
    private val torBoxRepository: TorBoxRepository,
    private val playerController: PlayerController,
    private val artworkResolver: StreamArtworkResolver,
) {
    /** Try a per-song torrent first, then fall back to the album torrent. */
    suspend fun playSong(
        artist: String, album: String, song: String, onProgress: (String) -> Unit,
    ): Result<Unit> {
        val first = resolveAndPlay("$artist $song", artist, album.ifBlank { song }, song, false, onProgress)
        if (first.isSuccess || album.isBlank()) return first
        return resolveAndPlay("$artist $album", artist, album, song, false, onProgress)
    }

    suspend fun playAlbum(
        artist: String, album: String, shuffle: Boolean, onProgress: (String) -> Unit,
    ): Result<Unit> = resolveAndPlay("$artist $album", artist, album, null, shuffle, onProgress)

    /** Stremio-style: list the torrent sources for a song (or album), cached-first. */
    suspend fun findSources(artist: String, album: String, song: String?): List<TorBoxSearchResult> {
        val queries = buildList {
            if (!song.isNullOrBlank()) add("$artist $song")
            if (album.isNotBlank()) add("$artist $album")
            if (isEmpty()) add(artist)
        }
        val all = queries.flatMap { torBoxRepository.search(it).getOrDefault(emptyList()) }
        return all.distinctBy { it.hash.ifBlank { it.name } }
            .sortedWith(
                // Cached first, then likely-playable (split FLAC/MP3 over APE / single
                // image+.cue), then by seeders.
                compareByDescending<TorBoxSearchResult> { it.cached }
                    .thenByDescending { it.isLikelyPlayable() }
                    .thenByDescending { it.seeders },
            )
            .take(MAX_SOURCES)
    }

    // APE isn't playable by the player, and "image + .cue" rips are a single huge
    // file (no per-track split) — deprioritize both.
    private fun TorBoxSearchResult.isLikelyPlayable(): Boolean {
        val n = name.lowercase()
        val singleImage = "image" in n && ".cue" in n
        val ape = Regex("\\bape\\b").containsMatchIn(n)
        return !singleImage && !ape
    }

    /** Play one specific source the user picked (album torrent; optionally start on a song). */
    suspend fun playResult(
        result: TorBoxSearchResult,
        displayArtist: String,
        displayAlbum: String,
        matchSong: String?,
        shuffle: Boolean,
        onProgress: (String) -> Unit,
    ): Result<Unit> = runCatching {
        onProgress("Voorbereiden…")
        var played = false
        var error: String? = null
        // patient = the user explicitly picked this source, so wait for TorBox to
        // download a non-cached torrent (and show live progress) instead of bailing.
        torBoxRepository.streamAlbum(result, patient = true).collect { st ->
            when (st) {
                is StreamState.ReadyAlbum -> {
                    playReadyAlbum(st, displayArtist, displayAlbum, matchSong, shuffle); played = true
                }
                is StreamState.Error -> error = st.message
                is StreamState.Preparing -> onProgress(
                    if (st.progress > 0f) "Downloaden ${(st.progress * 100).toInt()}%…" else "Voorbereiden…",
                )
                else -> {}
            }
        }
        if (!played) error(error ?: "Bron niet beschikbaar (niet gecached / weinig seeds)")
        Unit
    }

    private suspend fun resolveAndPlay(
        searchQuery: String,
        displayArtist: String,
        displayAlbum: String,
        matchSong: String?,
        shuffle: Boolean,
        onProgress: (String) -> Unit,
    ): Result<Unit> = runCatching {
        onProgress("Bron zoeken…")
        val results = torBoxRepository.search(searchQuery).getOrDefault(emptyList())
        if (results.isEmpty()) error("Geen bron gevonden")
        // Cached (instant) first, then the rest; try a few before giving up.
        val ordered = (results.filter { it.cached } + results.filterNot { it.cached }).take(MAX_TRY)
        var lastError: String? = null
        for (res in ordered) {
            var played = false
            var error: String? = null
            torBoxRepository.streamAlbum(res).collect { st ->
                when (st) {
                    is StreamState.ReadyAlbum -> {
                        playReadyAlbum(st, displayArtist, displayAlbum, matchSong, shuffle); played = true
                    }
                    is StreamState.Error -> error = st.message
                    is StreamState.Preparing -> onProgress("Voorbereiden…")
                    else -> {}
                }
            }
            if (played) return@runCatching Unit
            lastError = error
        }
        error(lastError ?: "Geen werkende bron")
    }

    private suspend fun playReadyAlbum(
        ready: StreamState.ReadyAlbum,
        artist: String,
        album: String,
        matchSong: String?,
        shuffle: Boolean,
    ) {
        val art = artworkResolver.resolve(artist, album, album)
        val tracks = ready.tracks.mapIndexed { index, at ->
            Track(
                id = -(index + 1L),
                title = at.file.shortName ?: at.file.name,
                artistName = artist,
                albumTitle = album,
                albumId = -1L,
                artistId = -1L,
                uri = at.url,
                durationMs = 0L,
                trackNumber = index + 1,
                discNumber = 1,
                year = null,
                artworkUri = art,
                genre = null,
                bitrate = null,
                sampleRate = null,
                isLossless = at.file.isFlac,
                fileSize = at.file.size,
                dateAdded = System.currentTimeMillis(),
            )
        }
        val startIndex = if (matchSong.isNullOrBlank()) 0 else {
            val needle = normalize(matchSong)
            tracks.indexOfFirst { normalize(it.title).contains(needle) }.let { if (it >= 0) it else 0 }
        }
        playerController.setShuffle(shuffle)
        playerController.playQueue(tracks, startIndex)
    }

    private fun normalize(s: String): String = s.lowercase().replace(Regex("[^a-z0-9]"), "")

    private companion object {
        const val MAX_TRY = 3
        const val MAX_SOURCES = 25
    }
}
