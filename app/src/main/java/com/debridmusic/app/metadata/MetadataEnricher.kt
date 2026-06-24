package com.debridmusic.app.metadata

import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.local.dao.AlbumDao
import com.debridmusic.app.data.local.dao.ArtistDao
import com.debridmusic.app.data.local.dao.TrackDao
import com.debridmusic.app.data.local.entity.AlbumEntity
import com.debridmusic.app.data.local.entity.ArtistEntity
import com.debridmusic.app.data.local.entity.TrackEntity
import com.debridmusic.app.data.remote.DiscogsAuthInterceptor
import com.debridmusic.app.data.remote.api.CoverArtArchiveApi
import com.debridmusic.app.data.remote.api.DeezerApi
import com.debridmusic.app.data.remote.api.DiscogsApi
import com.debridmusic.app.data.remote.api.LastFmApi
import com.debridmusic.app.data.remote.api.MusicBrainzApi
import com.debridmusic.app.data.remote.api.TheAudioDbApi
import com.debridmusic.app.data.remote.dto.bestCover
import com.debridmusic.app.data.remote.dto.bestFrontUrl
import com.debridmusic.app.data.remote.dto.bestImage
import com.debridmusic.app.data.remote.dto.genreName
import com.debridmusic.app.data.remote.dto.labelName
import com.debridmusic.app.data.remote.dto.primaryImage
import com.debridmusic.app.data.remote.dto.secondaryImage
import com.debridmusic.app.data.remote.dto.stripDiscogsMarkup
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import javax.inject.Inject
import javax.inject.Singleton

data class EnrichmentProgress(
    val current: Int,
    val total: Int,
    val currentItem: String = "",
) {
    val isDone get() = current >= total
    val fraction get() = if (total > 0) current.toFloat() / total else 0f
}

/**
 * Fills album/artist metadata (cover art, descriptions, artist images, banners,
 * bios, genres) from several FREE, keyless sources, in priority order, filling
 * only blanks so it's incremental and idempotent. Manual picks set
 * [AlbumEntity.manualOverride]/[ArtistEntity.manualOverride] so auto-enrichment
 * never overwrites a user's choice (unless force=true).
 */
@Singleton
class MetadataEnricher @Inject constructor(
    private val albumDao: AlbumDao,
    private val artistDao: ArtistDao,
    private val trackDao: TrackDao,
    private val musicBrainzApi: MusicBrainzApi,
    private val coverArtApi: CoverArtArchiveApi,
    private val lastFmApi: LastFmApi,
    private val deezerApi: DeezerApi,
    private val theAudioDbApi: TheAudioDbApi,
    private val discogsApi: DiscogsApi,
    private val discogsAuth: DiscogsAuthInterceptor,
    private val settingsStore: SettingsStore,
) {
    suspend fun enrichAll(
        onProgress: suspend (EnrichmentProgress) -> Unit = {},
    ): Int {
        var enriched = 0
        val albums = albumDao.observeAll().first()
        val artists = artistDao.observeAll().first()
        val lastFmKey = settingsStore.lastFmApiKey.first()
        val discogsToken = syncDiscogsToken()
        val total = albums.size + artists.size

        albums.forEachIndexed { idx, album ->
            onProgress(EnrichmentProgress(idx, total, album.title))
            if (enrichAlbum(album, discogsToken = discogsToken)) enriched++
            // Always backfill any track that still lacks a cover from its album,
            // even when the album itself needed no enrichment.
            backfillTrackArtwork(album.id)
            delay(MB_RATE_LIMIT_MS)
        }
        artists.forEachIndexed { idx, artist ->
            onProgress(EnrichmentProgress(albums.size + idx, total, artist.name))
            if (enrichArtist(artist, lastFmKey, discogsToken = discogsToken)) enriched++
            delay(MB_RATE_LIMIT_MS)
        }
        onProgress(EnrichmentProgress(total, total))
        return enriched
    }

    suspend fun reEnrichAlbum(albumId: Long): Boolean {
        val token = syncDiscogsToken()
        return albumDao.getById(albumId)?.let { enrichAlbum(it, force = true, discogsToken = token) } ?: false
    }

    suspend fun reEnrichArtist(artistId: Long): Boolean {
        val key = settingsStore.lastFmApiKey.first()
        val token = syncDiscogsToken()
        return artistDao.getById(artistId)?.let { enrichArtist(it, key, force = true, discogsToken = token) } ?: false
    }

    /** Pushes the saved Discogs token into the interceptor and returns it (blank = disabled). */
    private suspend fun syncDiscogsToken(): String =
        settingsStore.discogsToken.first().also { discogsAuth.token = it }

    // ── Album ───────────────────────────────────────────────────────────────────
    private suspend fun enrichAlbum(
        albumIn: AlbumEntity,
        force: Boolean = false,
        discogsToken: String = "",
    ): Boolean {
        if (!force && albumIn.manualOverride) return false
        // "Done" once the core fields are filled; a Deezer-matched album must also have
        // its record type (so existing albums re-run once to fetch type + official titles).
        if (!force && albumIn.artworkUri != null && albumIn.description != null &&
            albumIn.genre != null && albumIn.musicBrainzId != null &&
            (albumIn.deezerId == null || albumIn.recordType != null)) return false

        var a = albumIn
        var changed = false

        // 1. Deezer — cover + label + release date + genre (keyless, near-universal)
        runCatching {
            val hit = deezerApi.searchAlbum("${a.title} ${a.artistName}").data
                ?.firstOrNull { it.title?.contains(a.title, true) == true || a.title.contains(it.title ?: "##", true) }
                ?: deezerApi.searchAlbum("${a.title} ${a.artistName}").data?.firstOrNull()
            if (hit != null) {
                val full = runCatching { deezerApi.getAlbum(hit.id) }.getOrNull() ?: hit
                a = a.copy(
                    artworkUri = a.artworkUri ?: full.bestCover(),
                    genre = a.genre ?: full.genreName(),
                    label = a.label ?: full.label,
                    releaseDate = a.releaseDate ?: full.releaseDate,
                    year = a.year ?: full.releaseDate?.take(4)?.toIntOrNull(),
                    deezerId = a.deezerId ?: full.id,
                    recordType = a.recordType ?: full.recordType,
                )
                changed = true
            }
        }

        // 2. Discogs — cover + genre + label + year (needs the user's token)
        if (discogsToken.isNotBlank() && (a.artworkUri == null || a.genre == null || a.label == null)) {
            runCatching {
                val res = discogsApi.searchRelease(a.title.cleanForQuery(), a.artistName).results
                    ?.firstOrNull { it.type == "release" || it.type == "master" }
                if (res != null) {
                    val full = runCatching { discogsApi.getRelease(res.id) }.getOrNull()
                    a = a.copy(
                        artworkUri = a.artworkUri ?: full?.primaryImage() ?: res.bestImage(),
                        secondaryArtworkUri = a.secondaryArtworkUri ?: full?.secondaryImage(),
                        genre = a.genre ?: full?.genreName() ?: res.genre?.firstOrNull() ?: res.style?.firstOrNull(),
                        label = a.label ?: full?.labelName() ?: res.label?.firstOrNull(),
                        year = a.year ?: full?.year ?: res.year?.toIntOrNull(),
                        releaseDate = a.releaseDate ?: full?.released?.takeIf { it.length >= 8 },
                    )
                    changed = true
                }
            }
        }

        // 3. MusicBrainz + Cover Art Archive — MBID + cover fallback
        if (a.musicBrainzId == null || a.artworkUri == null) {
            runCatching {
                val best = musicBrainzApi.searchRelease(buildMbReleaseQuery(a.title, a.artistName))
                    .releases?.maxByOrNull { it.score ?: 0 }
                if (best != null) {
                    val art = if (a.artworkUri == null)
                        runCatching { coverArtApi.getCoverArt(best.id).bestFrontUrl() }.getOrNull() else a.artworkUri
                    a = a.copy(
                        musicBrainzId = a.musicBrainzId ?: best.id,
                        artworkUri = a.artworkUri ?: art,
                        year = a.year ?: best.date?.take(4)?.toIntOrNull(),
                        genre = a.genre ?: best.releaseGroup?.primaryType?.lowercase()
                            ?.replaceFirstChar { it.uppercase() },
                    )
                    changed = true
                }
            }
        }

        // 4. TheAudioDB — description + back cover + art/genre fallback
        if (a.description == null || a.secondaryArtworkUri == null || a.artworkUri == null) {
            runCatching {
                val tadb = a.musicBrainzId?.let { theAudioDbApi.albumByMbid(it).album?.firstOrNull() }
                    ?: theAudioDbApi.searchAlbum(a.artistName, a.title).album?.firstOrNull()
                if (tadb != null) {
                    a = a.copy(
                        description = a.description ?: tadb.description?.takeIf { it.isNotBlank() },
                        secondaryArtworkUri = a.secondaryArtworkUri ?: tadb.back?.takeIf { it.isNotBlank() },
                        artworkUri = a.artworkUri ?: (tadb.thumbHq ?: tadb.thumb)?.takeIf { it.isNotBlank() },
                        genre = a.genre ?: tadb.genre?.takeIf { it.isNotBlank() },
                        label = a.label ?: tadb.label?.takeIf { it.isNotBlank() },
                        theAudioDbId = a.theAudioDbId ?: tadb.idAlbum,
                    )
                    changed = true
                }
            }
        }

        // 5. Cross-fill: use the artist image if we still have no cover
        if (a.artworkUri == null) {
            artistDao.getById(a.artistId)?.imageUri?.let { a = a.copy(artworkUri = it); changed = true }
        }

        if (!changed && !force) return false
        albumDao.update(a)

        // Propagate the cover to this album's tracks (overwrite stale covers on force).
        backfillTrackArtwork(a.id, a.artworkUri, overwrite = force)
        // Replace torrent-filename track titles with official titles (Deezer→Discogs).
        alignTrackTitles(a.id, a, discogsToken)
        return changed
    }

    private data class OfficialTrack(val title: String, val position: Int)

    /**
     * Replaces local (torrent-filename) track titles with the official titles from
     * Deezer, falling back to Discogs when Deezer has no (good) match — many releases
     * (e.g. local/indie singles) only exist on Discogs. Safe by design: it picks the
     * source that best fits the local tracks and only renames on strong agreement, so a
     * wrong album match or bonus tracks never produce garbage titles.
     */
    private suspend fun alignTrackTitles(
        albumId: Long,
        a: AlbumEntity,
        discogsToken: String,
        deezerId: Long? = a.deezerId,
        discogsReleaseId: Long? = null,
    ) {
        val local = trackDao.observeByAlbum(albumId).first()
        if (local.isEmpty()) return

        var best = deezerId?.let { deezerTracklist(it) }.orEmpty()
        var bestScore = if (best.isNotEmpty()) avgBestSimilarity(local, best) else 0.0

        // Try Discogs when Deezer is missing or only a weak match.
        if (discogsToken.isNotBlank() && bestScore < 0.6) {
            val relId = discogsReleaseId ?: findDiscogsReleaseId(a)
            val discogs = relId?.let { discogsTracklist(it) }.orEmpty()
            if (discogs.isNotEmpty()) {
                val score = avgBestSimilarity(local, discogs)
                if (score > bestScore) { best = discogs; bestScore = score }
            }
        }
        if (best.isEmpty() || bestScore < 0.4) return // nothing fits → leave titles alone
        applyAlignment(local, best)
    }

    private suspend fun applyAlignment(local: List<TrackEntity>, official: List<OfficialTrack>) {
        val officialSorted = official.sortedBy { it.position }
        val localSorted = local.sortedBy { it.trackNumber }
        val positional = localSorted.size == officialSorted.size && run {
            localSorted.indices
                .map { titleSimilarity(localSorted[it].title, officialSorted[it].title) }
                .average() >= 0.5 // counts match AND titles broadly agree → trust positions
        }
        if (positional) {
            localSorted.forEachIndexed { i, t -> applyOfficial(t, officialSorted[i]) }
        } else {
            val used = HashSet<Int>()
            localSorted.forEach { t ->
                val idx = officialSorted.indices.filter { it !in used }
                    .maxByOrNull { titleSimilarity(t.title, officialSorted[it].title) } ?: return@forEach
                if (titleSimilarity(t.title, officialSorted[idx].title) >= 0.85) {
                    used.add(idx)
                    applyOfficial(t, officialSorted[idx])
                }
            }
        }
    }

    private suspend fun applyOfficial(track: TrackEntity, official: OfficialTrack) {
        if (track.title != official.title || track.trackNumber != official.position) {
            trackDao.update(track.copy(title = official.title, trackNumber = official.position))
        }
    }

    // Mean of each local track's best similarity to any official title — how well a
    // candidate tracklist fits this album.
    private fun avgBestSimilarity(local: List<TrackEntity>, official: List<OfficialTrack>): Double {
        if (official.isEmpty()) return 0.0
        return local.map { t -> official.maxOf { titleSimilarity(t.title, it.title) } }.average()
    }

    private suspend fun deezerTracklist(deezerAlbumId: Long): List<OfficialTrack> =
        runCatching { deezerApi.albumTracks(deezerAlbumId).data.orEmpty() }.getOrNull().orEmpty()
            .filter { !it.title.isNullOrBlank() }
            .sortedBy { it.trackPosition ?: Int.MAX_VALUE }
            .mapIndexed { i, t -> OfficialTrack(t.title!!.trim(), t.trackPosition ?: (i + 1)) }

    private suspend fun discogsTracklist(releaseId: Long): List<OfficialTrack> {
        val rel = runCatching { discogsApi.getRelease(releaseId) }.getOrNull() ?: return emptyList()
        return rel.tracklist.orEmpty()
            .filter { (it.type == null || it.type == "track") && !it.title.isNullOrBlank() }
            .mapIndexed { i, t -> OfficialTrack(t.title!!.trim(), i + 1) }
    }

    private suspend fun findDiscogsReleaseId(a: AlbumEntity): Long? = runCatching {
        discogsApi.searchRelease(a.title.cleanForQuery(), a.artistName).results
            ?.firstOrNull { it.type == "release" }?.id
    }.getOrNull()

    // 0..1 similarity of two track titles after stripping leading track numbers,
    // extensions and non-alphanumerics.
    private fun titleSimilarity(a: String, b: String): Double {
        val x = normalizeTitle(a)
        val y = normalizeTitle(b)
        if (x.isEmpty() || y.isEmpty()) return 0.0
        if (x == y) return 1.0
        val dist = levenshtein(x, y)
        return 1.0 - dist.toDouble() / maxOf(x.length, y.length)
    }

    private fun normalizeTitle(s: String): String =
        s.lowercase()
            .replace(Regex("^\\s*\\d{1,3}\\s*[-._)\\]]+\\s*"), "") // leading "01 - "
            .replace(Regex("\\.[a-z0-9]{2,4}$"), "")               // file extension
            .replace(Regex("[^a-z0-9]"), "")

    private fun levenshtein(a: String, b: String): Int {
        val dp = IntArray(b.length + 1) { it }
        for (i in 1..a.length) {
            var prev = dp[0]
            dp[0] = i
            for (j in 1..b.length) {
                val tmp = dp[j]
                dp[j] = minOf(
                    dp[j] + 1,
                    dp[j - 1] + 1,
                    prev + if (a[i - 1] == b[j - 1]) 0 else 1,
                )
                prev = tmp
            }
        }
        return dp[b.length]
    }

    /**
     * Aligns an album's tracks with its cover. By default only fills tracks that have
     * none; with [overwrite] it also replaces a stale/wrong cover (every track in an
     * album shares the album cover in this app).
     */
    private suspend fun backfillTrackArtwork(albumId: Long, knownArt: String? = null, overwrite: Boolean = false) {
        val art = knownArt ?: albumDao.getById(albumId)?.artworkUri ?: return
        if (art.isBlank()) return
        trackDao.observeByAlbum(albumId).first()
            .filter { if (overwrite) it.artworkUri != art else it.artworkUri.isNullOrBlank() }
            .forEach { trackDao.update(it.copy(artworkUri = art)) }
    }

    /**
     * Fast, network-free pass: align every track with its album cover. Fixes both
     * cover-less tracks and existing tracks left with a stale/broken cover from before
     * the album was enriched or manually corrected. Runs instantly (no rate limits).
     */
    suspend fun backfillTrackArtwork(): Int {
        var filled = 0
        albumDao.observeAll().first().forEach { album ->
            val art = album.artworkUri
            if (!art.isNullOrBlank()) {
                trackDao.observeByAlbum(album.id).first()
                    .filter { it.artworkUri != art }
                    .forEach { trackDao.update(it.copy(artworkUri = art)); filled++ }
            }
        }
        return filled
    }

    // ── Artist ──────────────────────────────────────────────────────────────────
    private suspend fun enrichArtist(
        artistIn: ArtistEntity,
        lastFmApiKey: String,
        force: Boolean = false,
        discogsToken: String = "",
    ): Boolean {
        if (!force && artistIn.manualOverride) return false
        if (!force && artistIn.biography != null && artistIn.imageUri != null &&
            artistIn.bannerUri != null && artistIn.genre != null) return false

        var ar = artistIn
        var changed = false

        // 1. Deezer — guaranteed artist image
        runCatching {
            val hit = deezerApi.searchArtist(ar.name).data
                ?.firstOrNull { it.name?.equals(ar.name, true) == true }
                ?: deezerApi.searchArtist(ar.name).data?.firstOrNull()
            if (hit != null) {
                ar = ar.copy(imageUri = ar.imageUri ?: hit.bestImage(), deezerId = ar.deezerId ?: hit.id)
                changed = true
            }
        }

        // 1b. Discogs — artist image + profile/bio (needs the user's token)
        if (discogsToken.isNotBlank() && (ar.imageUri == null || ar.biography == null)) {
            runCatching {
                val res = discogsApi.searchArtist(ar.name).results?.firstOrNull { it.type == "artist" }
                if (res != null) {
                    val full = runCatching { discogsApi.getArtist(res.id) }.getOrNull()
                    ar = ar.copy(
                        imageUri = ar.imageUri ?: full?.bestImage() ?: res.bestImage(),
                        biography = ar.biography ?: full?.profile?.stripDiscogsMarkup()?.takeIf { it.isNotBlank() },
                    )
                    changed = true
                }
            }
        }

        // 2. MusicBrainz — MBID
        if (ar.musicBrainzId == null) {
            runCatching {
                val best = musicBrainzApi.searchArtist("artist:\"${ar.name}\"").artists?.maxByOrNull { it.score ?: 0 }
                if (best != null) { ar = ar.copy(musicBrainzId = best.id); changed = true }
            }
        }

        // 3. TheAudioDB — bio + banner/fan-art + genre
        if (ar.biography == null || ar.bannerUri == null || ar.genre == null) {
            runCatching {
                val tadb = ar.musicBrainzId?.let { theAudioDbApi.artistByMbid(it).artists?.firstOrNull() }
                    ?: theAudioDbApi.searchArtist(ar.name).artists?.firstOrNull()
                if (tadb != null) {
                    ar = ar.copy(
                        biography = ar.biography ?: tadb.biography?.stripHtml()?.takeIf { it.isNotBlank() },
                        bannerUri = ar.bannerUri ?: listOf(tadb.fanart, tadb.banner, tadb.wideThumb)
                            .firstOrNull { !it.isNullOrBlank() },
                        secondaryImageUri = ar.secondaryImageUri ?: tadb.thumb?.takeIf { it.isNotBlank() },
                        imageUri = ar.imageUri ?: tadb.thumb?.takeIf { it.isNotBlank() },
                        genre = ar.genre ?: (tadb.genre ?: tadb.style)?.takeIf { it.isNotBlank() },
                        theAudioDbId = ar.theAudioDbId ?: tadb.idArtist,
                    )
                    changed = true
                }
            }
        }

        // 4. Last.fm — bio/image fallback (only if a key is configured)
        if (lastFmApiKey.isNotBlank() && (ar.biography == null || ar.imageUri == null)) {
            runCatching {
                delay(LASTFM_RATE_LIMIT_MS)
                val lfm = lastFmApi.getArtistInfo(artist = ar.name, apiKey = lastFmApiKey).artist
                if (lfm != null) {
                    val bio = lfm.bio?.summary?.stripHtml()?.trimLastFmSuffix()
                    val img = lfm.image?.lastOrNull { it.url.isNotBlank() && it.size == "extralarge" }?.url
                        ?: lfm.image?.lastOrNull { it.url.isNotBlank() }?.url
                    ar = ar.copy(
                        biography = ar.biography ?: bio?.takeIf { it.isNotBlank() },
                        imageUri = ar.imageUri ?: img?.takeIf { it.isNotBlank() },
                    )
                    changed = true
                }
            }
        }

        // 5. Cross-fill: use one of the artist's album covers if still no image
        if (ar.imageUri == null) {
            albumDao.observeByArtist(ar.id).first().firstNotNullOfOrNull { it.artworkUri }
                ?.let { ar = ar.copy(imageUri = it); changed = true }
        }

        if (!changed && !force) return false
        artistDao.update(ar)
        return changed
    }

    // ── Manual search ─────────────────────────────────────────────────────────────
    data class AlbumMatch(
        val source: String, val title: String, val artistName: String,
        val year: Int?, val thumbnailUrl: String?, val deezerId: Long?,
        val discogsReleaseId: Long? = null,
    )
    data class ArtistMatch(
        val source: String, val name: String, val imageUrl: String?, val deezerId: Long?,
        val discogsArtistId: Long? = null,
    )

    // Returns Deezer + Discogs (if a token is set) candidates so the picker shows both.
    suspend fun searchAlbumCandidates(query: String): List<AlbumMatch> {
        val deezer = runCatching {
            deezerApi.searchAlbum(query, limit = 12).data.orEmpty().mapNotNull { d ->
                val t = d.title ?: return@mapNotNull null
                AlbumMatch(
                    source = "Deezer", title = t, artistName = d.artist?.name ?: "",
                    year = d.releaseDate?.take(4)?.toIntOrNull(), thumbnailUrl = d.bestCover(), deezerId = d.id,
                )
            }
        }.getOrDefault(emptyList())
        val discogs = runCatching {
            if (syncDiscogsToken().isBlank()) emptyList()
            else discogsApi.search(query, type = "release").results.orEmpty()
                .filter { it.type == "release" || it.type == "master" }
                .mapNotNull { r ->
                    val raw = r.title ?: return@mapNotNull null
                    val (artist, title) = splitDiscogsTitle(raw)
                    AlbumMatch(
                        source = "Discogs", title = title, artistName = artist,
                        year = r.year?.toIntOrNull(), thumbnailUrl = r.bestImage(),
                        deezerId = null, discogsReleaseId = r.id.takeIf { r.type == "release" },
                    )
                }
        }.getOrDefault(emptyList())
        return deezer + discogs
    }

    suspend fun searchArtistCandidates(query: String): List<ArtistMatch> {
        val deezer = runCatching {
            deezerApi.searchArtist(query, limit = 12).data.orEmpty().mapNotNull { d ->
                val n = d.name ?: return@mapNotNull null
                ArtistMatch(source = "Deezer", name = n, imageUrl = d.bestImage(), deezerId = d.id)
            }
        }.getOrDefault(emptyList())
        val discogs = runCatching {
            if (syncDiscogsToken().isBlank()) emptyList()
            else discogsApi.search(query, type = "artist").results.orEmpty()
                .filter { it.type == "artist" }
                .mapNotNull { r ->
                    val n = r.title ?: return@mapNotNull null
                    ArtistMatch(source = "Discogs", name = n, imageUrl = r.bestImage(), deezerId = null, discogsArtistId = r.id)
                }
        }.getOrDefault(emptyList())
        return deezer + discogs
    }

    suspend fun applyAlbumMatch(albumId: Long, m: AlbumMatch) {
        val album = albumDao.getById(albumId) ?: return
        val deezerFull = m.deezerId?.let { runCatching { deezerApi.getAlbum(it) }.getOrNull() }
        val discogsFull = m.discogsReleaseId?.let {
            syncDiscogsToken(); runCatching { discogsApi.getRelease(it) }.getOrNull()
        }
        val updated = album.copy(
            artworkUri = deezerFull?.bestCover() ?: discogsFull?.primaryImage() ?: m.thumbnailUrl ?: album.artworkUri,
            genre = deezerFull?.genreName() ?: discogsFull?.genreName() ?: album.genre,
            label = deezerFull?.label ?: discogsFull?.labelName() ?: album.label,
            releaseDate = deezerFull?.releaseDate ?: discogsFull?.released?.takeIf { it.length >= 8 } ?: album.releaseDate,
            year = (deezerFull?.releaseDate?.take(4)?.toIntOrNull()) ?: discogsFull?.year ?: m.year ?: album.year,
            deezerId = m.deezerId ?: album.deezerId,
            recordType = deezerFull?.recordType ?: album.recordType,
            // reset stale fields so backfill re-fetches description/back for the new album
            description = null, secondaryArtworkUri = null, musicBrainzId = null, theAudioDbId = null,
            manualOverride = true,
        )
        albumDao.update(updated)
        // Apply the chosen album's official track titles (Deezer or Discogs).
        alignTrackTitles(albumId, updated, syncDiscogsToken(), m.deezerId, m.discogsReleaseId)
        // Backfill description/back-cover from other sources for the chosen album.
        enrichAlbum(updated.copy(manualOverride = false), force = true)
        // Re-assert the override flag (enrichAlbum wrote manualOverride=false copy's value).
        albumDao.getById(albumId)?.let { albumDao.update(it.copy(manualOverride = true)) }
    }

    suspend fun applyArtistMatch(artistId: Long, m: ArtistMatch) {
        val artist = artistDao.getById(artistId) ?: return
        val deezerFull = m.deezerId?.let { runCatching { deezerApi.getArtist(it) }.getOrNull() }
        val discogsFull = m.discogsArtistId?.let {
            syncDiscogsToken(); runCatching { discogsApi.getArtist(it) }.getOrNull()
        }
        val updated = artist.copy(
            imageUri = deezerFull?.bestImage() ?: discogsFull?.bestImage() ?: m.imageUrl ?: artist.imageUri,
            deezerId = m.deezerId ?: artist.deezerId,
            // keep the Discogs bio if the user picked a Discogs artist; else let backfill fetch one
            biography = discogsFull?.profile?.stripDiscogsMarkup()?.takeIf { it.isNotBlank() },
            bannerUri = null, musicBrainzId = null, theAudioDbId = null,
            manualOverride = true,
        )
        artistDao.update(updated)
        val key = settingsStore.lastFmApiKey.first()
        enrichArtist(updated.copy(manualOverride = false), key, force = true)
        artistDao.getById(artistId)?.let { artistDao.update(it.copy(manualOverride = true)) }
    }

    // Discogs release titles are "Artist - Album"; split into (artist, album).
    private fun splitDiscogsTitle(t: String): Pair<String, String> {
        val idx = t.indexOf(" - ")
        return if (idx > 0) t.substring(0, idx).trim() to t.substring(idx + 3).trim() else "" to t.trim()
    }

    private fun buildMbReleaseQuery(albumTitle: String, artistName: String): String {
        val cleanAlbum = albumTitle.cleanForQuery().replace("\"", "\\\"")
        val cleanArtist = artistName.replace("\"", "\\\"")
        return "release:\"$cleanAlbum\" AND artist:\"$cleanArtist\""
    }

    // Strip year/format noise that hurts MusicBrainz match rate.
    private fun String.cleanForQuery(): String =
        replace(Regex("\\[[^\\]]*\\]"), " ")
            .replace(Regex("\\((?:19|20)\\d{2}\\)"), " ")
            .replace(Regex("(?i)\\b(flac|mp3|320|256|192|kbps|web|vinyl|remaster(ed)?)\\b"), " ")
            .replace(Regex("\\s+"), " ").trim()

    companion object {
        private const val MB_RATE_LIMIT_MS = 1100L
        private const val LASTFM_RATE_LIMIT_MS = 250L
    }
}

private fun String.stripHtml(): String =
    replace(Regex("<[^>]+>"), "").replace("&amp;", "&").replace("&quot;", "\"")
        .replace("&lt;", "<").replace("&gt;", ">").replace("&apos;", "'")
        .replace(Regex("\\s+"), " ").trim()

private fun String.trimLastFmSuffix(): String {
    val cutMarker = "<a href=\"https://www.last.fm"
    val idx = indexOf(cutMarker)
    return if (idx > 0) substring(0, idx).trim().trimEnd('.').trim() else this
}
