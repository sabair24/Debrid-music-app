package com.debridmusic.app.ui.browse

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.LibraryAdd
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.debridmusic.app.ui.components.AlbumArtwork
import com.debridmusic.app.ui.components.MiniPlayer

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AlbumBrowseScreen(
    onBack: () -> Unit,
    onNowPlayingClick: () -> Unit,
    viewModel: AlbumBrowseViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val currentTrack by viewModel.playerController.currentTrack.collectAsStateWithLifecycle()
    val isPlaying by viewModel.playerController.isPlaying.collectAsStateWithLifecycle()
    val positionMs by viewModel.playerController.positionMs.collectAsStateWithLifecycle()
    val durationMs by viewModel.playerController.durationMs.collectAsStateWithLifecycle()

    val album = state.album

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(album?.title ?: "Album", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, "Terug") } },
            )
        },
        bottomBar = {
            currentTrack?.let { track ->
                MiniPlayer(
                    track = track,
                    isPlaying = isPlaying,
                    progress = if (durationMs > 0) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f,
                    onPlayPause = { viewModel.playerController.togglePlayPause() },
                    onSkipNext = { viewModel.playerController.skipToNext() },
                    onClick = onNowPlayingClick,
                )
            }
        },
    ) { padding ->
        when {
            state.isLoading -> Box(Modifier.fillMaxSize().padding(padding), Alignment.Center) { CircularProgressIndicator() }
            else -> LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
                item {
                    Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        AlbumArtwork(uri = album?.artworkUri, size = 180.dp, cornerRadius = 8.dp)
                        Spacer(Modifier.height(12.dp))
                        Text(album?.title ?: "", style = MaterialTheme.typography.titleLarge)
                        Text(
                            buildString {
                                append(album?.artist.orEmpty())
                                album?.year?.let { append(" • $it") }
                            },
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.height(12.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Button(onClick = { viewModel.showAlbumSources(shuffle = false) }) {
                                Icon(Icons.Default.PlayArrow, null, Modifier.size(18.dp))
                                Spacer(Modifier.width(6.dp))
                                Text("Speel album")
                            }
                            OutlinedButton(onClick = { viewModel.showAlbumSources(shuffle = true) }) {
                                Icon(Icons.Default.Shuffle, null, Modifier.size(18.dp))
                                Spacer(Modifier.width(6.dp))
                                Text("Shuffle")
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            OutlinedButton(onClick = { viewModel.saveToLibrary() }, enabled = !state.addBusy) {
                                Icon(Icons.Default.LibraryAdd, null, Modifier.size(18.dp))
                                Spacer(Modifier.width(6.dp))
                                Text("Bewaar")
                            }
                            OutlinedButton(onClick = { viewModel.downloadToLibrary() }, enabled = !state.addBusy) {
                                Icon(Icons.Default.Download, null, Modifier.size(18.dp))
                                Spacer(Modifier.width(6.dp))
                                Text("Download")
                            }
                        }
                        state.addStatus?.let { msg ->
                            Spacer(Modifier.height(6.dp))
                            Text(msg, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
                items(state.tracks) { track ->
                    BrowseTrackRow(track.position.takeIf { it > 0 } ?: 1, track) { viewModel.showSourcesForTrack(track) }
                }
                item { Spacer(Modifier.height(16.dp)) }
            }
        }
    }

    state.sourcePicker?.let { picker ->
        SourcePickerSheet(
            picker = picker,
            onPick = { viewModel.pickSource(it) },
            onDismiss = { viewModel.dismissSources() },
        )
    }
}
