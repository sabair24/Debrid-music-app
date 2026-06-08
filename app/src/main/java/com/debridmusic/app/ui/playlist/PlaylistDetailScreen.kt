package com.debridmusic.app.ui.playlist

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.debridmusic.app.ui.components.MiniPlayer
import com.debridmusic.app.ui.components.TrackItem

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaylistDetailScreen(
    onBack: () -> Unit,
    onNowPlayingClick: () -> Unit,
    viewModel: PlaylistDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val currentTrack by viewModel.playerController.currentTrack.collectAsStateWithLifecycle()
    val isPlaying by viewModel.playerController.isPlaying.collectAsStateWithLifecycle()
    val positionMs by viewModel.playerController.positionMs.collectAsStateWithLifecycle()
    val durationMs by viewModel.playerController.durationMs.collectAsStateWithLifecycle()
    val progress = if (durationMs > 0) positionMs.toFloat() / durationMs else 0f

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = state.playlistName,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, "Back") }
                },
                actions = {
                    if (state.tracks.isNotEmpty()) {
                        IconButton(onClick = { viewModel.playAll(); onNowPlayingClick() }) {
                            Icon(Icons.Default.PlayArrow, "Play all")
                        }
                    }
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
        if (state.tracks.isEmpty()) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxSize().padding(padding).padding(32.dp),
            ) {
                Text(
                    "This playlist is empty.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            LazyColumn(
                contentPadding = PaddingValues(vertical = 8.dp),
                modifier = Modifier.fillMaxSize().padding(padding),
            ) {
                itemsIndexed(state.tracks, key = { _, t -> t.id }) { _, track ->
                    TrackItem(
                        track = track,
                        isPlaying = isPlaying && track.id == currentTrack?.id,
                        onTrackClick = { t ->
                            viewModel.playTrack(t)
                            onNowPlayingClick()
                        },
                        onMoreClick = { t -> viewModel.removeTrack(t.id) },
                    )
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                        modifier = Modifier.padding(start = 76.dp),
                    )
                }
            }
        }
    }
}
