package com.debridmusic.app.metadata

import com.debridmusic.app.data.local.SettingsStore
import com.debridmusic.app.data.local.dao.AlbumDao
import com.debridmusic.app.data.local.dao.ArtistDao
import com.debridmusic.app.data.local.dao.TrackDao
import com.debridmusic.app.data.local.entity.AlbumEntity
import com.debridmusic.app.data.local.entity.ArtistEntity
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
        if (!force && albumIn.artworkUri != null && albumIn.description != null &&
            albumIn.genre != null && albumIn.musicBrainzId != null) return false

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

        // Propagate artwork to tracks that lack it
        a.artworkUri?.let { art ->
            trackDao.observeByAlbum(a.id).first()
                .filter { it.artworkUri == null }
                .forEach { trackDao.update(it.copy(artworkUri = art)) }
        }
        return changed
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
    )
    data class ArtistMatch(
        val source: String, val name: String, val imageUrl: String?, val deezerId: Long?,
    )

    suspend fun searchAlbumCandidates(query: String): List<AlbumMatch> = runCatching {
        deezerApi.searchAlbum(query, limit = 12).data.orEmpty().mapNotNull { d ->
            val t = d.title ?: return@mapNotNull null
            AlbumMatch(
                source = "Deezer", title = t, artistName = d.artist?.name ?: "",
                year = d.releaseDate?.take(4)?.toIntOrNull(), thumbnailUrl = d.bestCover(), deezerId = d.id,
            )
        }
    }.getOrDefault(emptyList())

    suspend fun searchArtistCandidates(query: String): List<ArtistMatch> = runCatching {
        deezerApi.searchArtist(query, limit = 12).data.orEmpty().mapNotNull { d ->
            val n = d.name ?: return@mapNotNull null
            ArtistMatch(source = "Deezer", name = n, imageUrl = d.bestImage(), deezerId = d.id)
        }
    }.getOrDefault(emptyList())

    suspend fun applyAlbumMatch(albumId: Long, m: AlbumMatch) {
        val album = albumDao.getById(albumId) ?: return
        val full = m.deezerId?.let { runCatching { deezerApi.getAlbum(it) }.getOrNull() }
        val updated = album.copy(
            artworkUri = full?.bestCover() ?: m.thumbnailUrl ?: album.artworkUri,
            genre = full?.genreName() ?: album.genre,
            label = full?.label ?: album.label,
            releaseDate = full?.releaseDate ?: album.releaseDate,
            year = (full?.releaseDate?.take(4)?.toIntOrNull()) ?: m.year ?: album.year,
            deezerId = m.deezerId ?: album.deezerId,
            // reset stale fields so backfill re-fetches description/back for the new album
            description = null, secondaryArtworkUri = null, musicBrainzId = null, theAudioDbId = null,
            manualOverride = true,
        )
        albumDao.update(updated)
        // Backfill description/back-cover from other sources for the chosen album.
        enrichAlbum(updated.copy(manualOverride = false), force = true)
        // Re-assert the override flag (enrichAlbum wrote manualOverride=false copy's value).
        albumDao.getById(albumId)?.let { albumDao.update(it.copy(manualOverride = true)) }
    }

    suspend fun applyArtistMatch(artistId: Long, m: ArtistMatch) {
        val artist = artistDao.getById(artistId) ?: return
        val full = m.deezerId?.let { runCatching { deezerApi.getArtist(it) }.getOrNull() }
        val updated = artist.copy(
            imageUri = full?.bestImage() ?: m.imageUrl ?: artist.imageUri,
            deezerId = m.deezerId ?: artist.deezerId,
            biography = null, bannerUri = null, musicBrainzId = null, theAudioDbId = null,
            manualOverride = true,
        )
        artistDao.update(updated)
        val key = settingsStore.lastFmApiKey.first()
        enrichArtist(updated.copy(manualOverride = false), key, force = true)
        artistDao.getById(artistId)?.let { artistDao.update(it.copy(manualOverride = true)) }
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
