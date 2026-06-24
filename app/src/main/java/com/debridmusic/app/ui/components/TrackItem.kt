package com.debridmusic.app.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.debridmusic.app.domain.model.Track

@Composable
fun TrackItem(
    track: Track,
    isPlaying: Boolean = false,
    onTrackClick: (Track) -> Unit,
    onMoreClick: ((Track) -> Unit)? = null,
    showArtwork: Boolean = true,
    showAlbum: Boolean = true,
    fallbackArtworkUri: String? = null,
    modifier: Modifier = Modifier,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .fillMaxWidth()
            .clickable { onTrackClick(track) }
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        if (showArtwork) {
            // Fall back to the album cover when the track itself has no artwork.
            AlbumArtwork(uri = track.artworkUri?.takeIf { it.isNotBlank() } ?: fallbackArtworkUri, size = 48.dp)
            Spacer(Modifier.width(12.dp))
        }

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = track.title,
                style = MaterialTheme.typography.titleMedium,
                color = if (isPlaying)
                    MaterialTheme.colorScheme.primary
                else
                    MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (track.isLossless) {
                    Text(
                        text = "FLAC",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(end = 4.dp),
                    )
                }
                Text(
                    text = buildString {
                        append(track.artistName)
                        if (showAlbum && track.albumTitle.isNotBlank()) {
                            append(" • ")
                            append(track.albumTitle)
                        }
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        Text(
            text = track.formattedDuration,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 8.dp),
        )

        if (onMoreClick != null) {
            IconButton(onClick = { onMoreClick(track) }) {
                Icon(
                    imageVector = Icons.Default.MoreVert,
                    contentDescription = "More",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
