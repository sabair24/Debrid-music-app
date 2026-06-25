package com.debridmusic.app.data.local.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "tracks",
    foreignKeys = [
        ForeignKey(
            entity = AlbumEntity::class,
            parentColumns = ["id"],
            childColumns = ["albumId"],
            onDelete = ForeignKey.SET_NULL,
        ),
        ForeignKey(
            entity = ArtistEntity::class,
            parentColumns = ["id"],
            childColumns = ["artistId"],
            onDelete = ForeignKey.SET_NULL,
        ),
    ],
    indices = [Index("albumId"), Index("artistId"), Index("uri", unique = true)]
)
data class TrackEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val title: String,
    val artistName: String,
    val albumTitle: String,
    val albumId: Long?,
    val artistId: Long?,
    val uri: String,
    val durationMs: Long,
    val trackNumber: Int = 0,
    val discNumber: Int = 1,
    val year: Int? = null,
    val artworkUri: String? = null,
    val genre: String? = null,
    val bitrate: Int? = null,
    val sampleRate: Int? = null,
    val isLossless: Boolean = false,
    val fileSize: Long = 0,
    val dateAdded: Long = System.currentTimeMillis(),
    // "local" = playable file in `uri`; "online" = torrent-backed, re-resolved on
    // play using torrentHash + torrentFileName.
    val sourceType: String = "local",
    val torrentHash: String? = null,
    val torrentFileName: String? = null,
    // "server" tracks live on the user's self-hosted music server; the stream URL in
    // `uri` is refreshed from this id (+ current server URL/token) before playback.
    val serverTrackId: String? = null,
)
