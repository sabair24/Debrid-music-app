package com.debridmusic.app.ui.album

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import com.debridmusic.app.ui.metadata.MetadataCandidate
import com.debridmusic.app.ui.metadata.MetadataEditorDialog
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.debridmusic.app.ui.theme.rememberDominantColor
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import com.debridmusic.app.ui.components.MiniPlayer
import com.debridmusic.app.ui.components.TrackItem

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AlbumDetailScreen(
    onBack: () -> Unit,
    onNowPlayingClick: () -> Unit,
    viewModel: AlbumDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val currentTrack by viewModel.playerController.currentTrack.collectAsStateWithLifecycle()
    val isPlaying by viewModel.playerController.isPlaying.collectAsStateWithLifecycle()
    val positionMs by viewModel.playerController.positionMs.collectAsStateWithLifecycle()
    val durationMs by viewModel.playerController.durationMs.collectAsStateWithLifecycle()

    val progress = if (durationMs > 0) positionMs.toFloat() / durationMs else 0f
    val accent by rememberDominantColor(state.album?.artworkUri, MaterialTheme.colorScheme.primary)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(state.album?.title ?: "") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, "Back")
                    }
                },
                actions = {
                    if (state.refreshing) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(8.dp))
                    }
                    IconButton(onClick = viewModel::reEnrich) { Icon(Icons.Default.Refresh, "Metadata verversen") }
                    IconButton(onClick = viewModel::openEditor) { Icon(Icons.Default.Edit, "Metadata zoeken") }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
        bottomBar = {
            if (currentTrack != null) {
                MiniPlayer(
                    track = currentTrack,
                    isPlaying = isPlaying,
                    progress = progress,
                    onPlayPause = { viewModel.playerController.togglePlayPause() },
                    onSkipNext = { viewModel.playerController.skipToNext() },
                    onClick = onNowPlayingClick,
                )
            }
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // Album header
            item {
                Box(modifier = Modifier.fillMaxWidth().height(280.dp)) {
                    // Blurred backdrop
                    state.album?.artworkUri?.let { uri ->
                        AsyncImage(
                            model = uri,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize().blur(40.dp),
                        )
                    } ?: Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(accent.copy(alpha = 0.35f))
                    )
                    // Dynamic colour gradient overlay
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(
                                Brush.verticalGradient(
                                    0.0f to accent.copy(alpha = 0.35f),
                                    0.6f to MaterialTheme.colorScheme.background.copy(alpha = 0.85f),
                                    1.0f to MaterialTheme.colorScheme.background,
                                )
                            )
                    )
                    // Album artwork + info
                    Row(
                        verticalAlignment = Alignment.Bottom,
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(16.dp),
                    ) {
                        state.album?.artworkUri?.let { uri ->
                            AsyncImage(
                                model = uri,
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier
                                    .size(120.dp)
                                    .let { it },
                            )
                        }
                        Spacer(Modifier.width(16.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = state.album?.title ?: "",
                                style = MaterialTheme.typography.headlineMedium,
                                color = MaterialTheme.colorScheme.onBackground,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Text(
                                text = state.album?.artistName ?: "",
                                style = MaterialTheme.typography.titleMedium,
                                color = MaterialTheme.colorScheme.primary,
                            )
                            state.album?.year?.let { year ->
                                Text(
                                    text = buildString {
                                        append(year)
                                        state.album?.genre?.let { append(" • $it") }
                                        append(" • ${state.tracks.size} tracks")
                                    },
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            state.album?.musicBrainzId?.let {
                                Text(
                                    text = "MusicBrainz verified",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.primary.copy(alpha = 0.7f),
                                )
                            }
                        }
                    }
                }
            }

            // Play all button
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Button(
                        onClick = viewModel::playAll,
                        colors = ButtonDefaults.buttonColors(containerColor = accent, contentColor = Color.White),
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Default.PlayArrow, null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("Play all")
                    }
                }
            }

            // Enriched album info (label + description)
            state.album?.let { al ->
                if (!al.label.isNullOrBlank() || !al.description.isNullOrBlank()) {
                    item {
                        Column(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            al.label?.takeIf { it.isNotBlank() }?.let {
                                Text("Label · $it", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            al.description?.takeIf { it.isNotBlank() }?.let {
                                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 8, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                }
            }

            // Track list
            itemsIndexed(state.tracks, key = { _, t -> t.id }) { _, track ->
                TrackItem(
                    track = track,
                    isPlaying = isPlaying && track.id == currentTrack?.id,
                    onTrackClick = { t ->
                        viewModel.playTrack(t)
                        onNowPlayingClick()
                    },
                    showArtwork = true,
                    showAlbum = false,
                    fallbackArtworkUri = state.album?.artworkUri,
                )
                HorizontalDivider(
                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                    modifier = Modifier.padding(start = 16.dp),
                )
            }
        }
    }

    if (state.editorOpen) {
        MetadataEditorDialog(
            title = "Albummetadata zoeken",
            initialQuery = listOfNotNull(state.album?.title, state.album?.artistName).joinToString(" "),
            searching = state.searching,
            candidates = state.candidates.map {
                MetadataCandidate(
                    title = it.title,
                    subtitle = listOfNotNull(it.artistName.ifBlank { null }, it.year?.toString()).joinToString(" · "),
                    thumbnailUrl = it.thumbnailUrl,
                    source = it.source,
                )
            },
            onSearch = viewModel::searchMetadata,
            onPick = { idx -> viewModel.applyMatch(state.candidates[idx]) },
            onDismiss = viewModel::closeEditor,
        )
    }
}
