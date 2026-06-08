package com.debridmusic.app.scanner

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.MediaStore
import com.debridmusic.app.data.local.dao.AlbumDao
import com.debridmusic.app.data.local.dao.ArtistDao
import com.debridmusic.app.data.local.dao.TrackDao
import com.debridmusic.app.data.local.entity.AlbumEntity
import com.debridmusic.app.data.local.entity.ArtistEntity
import com.debridmusic.app.data.local.entity.TrackEntity
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class MediaScanner @Inject constructor(
    @ApplicationContext private val context: Context,
    private val trackDao: TrackDao,
    private val albumDao: AlbumDao,
    private val artistDao: ArtistDao,
) {
    private val resolver: ContentResolver get() = context.contentResolver

    private val LOSSLESS_EXTS = setOf("flac", "alac", "wav", "aiff", "ape", "wv", "tta")

    suspend fun scanDevice(): Int = withContext(Dispatchers.IO) {
        var imported = 0
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.ARTIST_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.YEAR,
            MediaStore.Audio.Media.MIME_TYPE,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.BITRATE,
            MediaStore.Audio.Media.DATA,
        )

        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val sortOrder = "${MediaStore.Audio.Media.ARTIST} ASC, ${MediaStore.Audio.Media.ALBUM} ASC, ${MediaStore.Audio.Media.TRACK} ASC"

        resolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            null,
            sortOrder,
        )?.use { cursor ->
            imported = processCursor(cursor)
        }
        imported
    }

    private suspend fun processCursor(cursor: Cursor): Int {
        val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
        val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
        val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
        val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
        val albumIdCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
        val artistIdCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST_ID)
        val durationCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
        val trackCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
        val yearCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)
        val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
        val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
        val dateAddedCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
        val bitrateCol = cursor.getColumnIndex(MediaStore.Audio.Media.BITRATE)
        val dataCol = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)

        var count = 0
        while (cursor.moveToNext()) {
            val mediaId = cursor.getLong(idCol)
            val contentUri = ContentUris.withAppendedId(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, mediaId
            )

            val title = cursor.getString(titleCol) ?: "Unknown"
            val artistName = cursor.getString(artistCol)?.takeIf { it != "<unknown>" } ?: "Unknown Artist"
            val albumTitle = cursor.getString(albumCol) ?: "Unknown Album"
            val mediaAlbumId = cursor.getLong(albumIdCol)
            val mediaArtistId = cursor.getLong(artistIdCol)
            val duration = cursor.getLong(durationCol)
            val trackRaw = cursor.getInt(trackCol)
            val trackNum = trackRaw % 1000
            val discNum = if (trackRaw >= 1000) trackRaw / 1000 else 1
            val year = cursor.getInt(yearCol).takeIf { it > 0 }
            val mimeType = cursor.getString(mimeCol) ?: ""
            val size = cursor.getLong(sizeCol)
            val dateAdded = cursor.getLong(dateAddedCol) * 1000L
            val bitrate = if (bitrateCol >= 0) cursor.getInt(bitrateCol).takeIf { it > 0 } else null
            val filePath = if (dataCol >= 0) cursor.getString(dataCol) else null
            val ext = filePath?.substringAfterLast('.')?.lowercase() ?: ""
            val isLossless = mimeType.contains("flac") || mimeType.contains("wav") ||
                    mimeType.contains("x-alac") || ext in LOSSLESS_EXTS

            val artworkUri = getAlbumArtUri(mediaAlbumId)?.toString()

            // Upsert artist
            val dbArtistId = getOrCreateArtist(artistName)

            // Upsert album
            val dbAlbumId = getOrCreateAlbum(albumTitle, dbArtistId, artistName, year, artworkUri)

            val track = TrackEntity(
                title = title,
                artistName = artistName,
                albumTitle = albumTitle,
                albumId = dbAlbumId,
                artistId = dbArtistId,
                uri = contentUri.toString(),
                durationMs = duration,
                trackNumber = trackNum,
                discNumber = discNum,
                year = year,
                artworkUri = artworkUri,
                genre = null,
                bitrate = bitrate,
                sampleRate = null,
                isLossless = isLossless,
                fileSize = size,
                dateAdded = dateAdded,
            )

            val inserted = trackDao.insert(track)
            if (inserted > 0) count++
        }
        return count
    }

    private suspend fun getOrCreateArtist(name: String): Long {
        val existing = artistDao.getByName(name)
        if (existing != null) return existing.id
        return artistDao.insert(ArtistEntity(name = name))
    }

    private suspend fun getOrCreateAlbum(
        title: String,
        artistId: Long,
        artistName: String,
        year: Int?,
        artworkUri: String?,
    ): Long {
        val existing = albumDao.getByTitleAndArtist(title, artistId)
        if (existing != null) return existing.id
        return albumDao.insert(
            AlbumEntity(
                title = title,
                artistId = artistId,
                artistName = artistName,
                year = year,
                artworkUri = artworkUri,
            )
        )
    }

    private fun getAlbumArtUri(albumId: Long): Uri? {
        return try {
            ContentUris.withAppendedId(
                Uri.parse("content://media/external/audio/albumart"), albumId
            )
        } catch (_: Exception) { null }
    }
}
