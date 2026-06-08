package com.debridmusic.app.ui.catalogue

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Album
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.torbox.StreamState
import com.debridmusic.app.ui.components.MiniPlayer
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CatalogueSearchScreen(
    onBack: () -> Unit,
    onNowPlayingClick: () -> Unit,
    viewModel: CatalogueSearchViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val currentTrack by viewModel.playerController.currentTrack.collectAsStateWithLifecycle()
    val isPlaying by viewModel.playerController.isPlaying.collectAsStateWithLifecycle()
    val positionMs by viewModel.playerController.positionMs.collectAsStateWithLifecycle()
    val durationMs by viewModel.playerController.durationMs.collectAsStateWithLifecycle()

    val focusRequester = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val progress = if (durationMs > 0) positionMs.toFloat() / durationMs else 0f

    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    TextField(
                        value = state.query,
                        onValueChange = viewModel::setQuery,
                        placeholder = { Text("Artist · Album · Track…") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        keyboardActions = KeyboardActions(onSearch = {
                            keyboard?.hide()
                            viewModel.search()
                        }),
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = MaterialTheme.colorScheme.surface,
                            unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                            focusedIndicatorColor = MaterialTheme.colorScheme.primary,
                        ),
                        modifier = Modifier
                            .fillMaxWidth()
                            .focusRequester(focusRequester),
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, "Back")
                    }
                },
                actions = {
                    if (state.query.isNotBlank()) {
                        IconButton(onClick = { viewModel.setQuery("") }) {
                            Icon(Icons.Default.Close, "Clear")
                        }
                    }
                    IconButton(onClick = {
                        keyboard?.hide()
                        viewModel.search()
                    }) {
                        Icon(Icons.Default.Search, "Search")
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
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            when {
                state.isSearching -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                            Spacer(Modifier.height(12.dp))
                            Text("Searching TorBox…", style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }

                state.searchError != null -> {
                    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                text = "Search error",
                                style = MaterialTheme.typography.titleMedium,
                                color = MaterialTheme.colorScheme.error,
                            )
                            Spacer(Modifier.height(8.dp))
                            Text(
                                text = state.searchError ?: "",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }

                state.results.isEmpty() && state.query.isBlank() -> {
                    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                        Text(
                            text = "Search for an artist, album, or track.\nTorBox will stream FLAC directly to you.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }

                state.results.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text("No results", style = MaterialTheme.typography.bodyMedium)
                    }
                }

                else -> {
                    LazyColumn(contentPadding = PaddingValues(vertical = 8.dp)) {
                        items(state.results, key = { it.hash.ifBlank { it.name } }) { result ->
                            TorBoxResultItem(
                                result = result,
                                isStreaming = state.streamingId == result.hash,
                                streamState = if (state.streamingId == result.hash) state.streamState
                                else StreamState.Idle,
                                isDownloading = state.downloadingHash == result.hash,
                                onStream = { viewModel.stream(result) },
                                onStreamAlbum = { viewModel.stream(result, albumMode = true) },
                                onCancel = { viewModel.cancelStream() },
                                onNowPlaying = onNowPlayingClick,
                                onDownload = { viewModel.downloadCurrentStream() },
                            )
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.25f),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TorBoxResultItem(
    result: TorBoxSearchResult,
    isStreaming: Boolean,
    streamState: StreamState,
    isDownloading: Boolean,
    onStream: () -> Unit,
    onStreamAlbum: () -> Unit,
    onCancel: () -> Unit,
    onNowPlaying: () -> Unit,
    onDownload: () -> Unit,
) {
    val isFlac = result.name.contains("flac", ignoreCase = true)
    val isMp3 = result.name.contains("mp3", ignoreCase = true) || result.name.contains("320", ignoreCase = false)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Column(modifier = Modifier.weight(1f)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    if (isFlac) FormatBadge("FLAC", MaterialTheme.colorScheme.primary)
                    else if (isMp3) FormatBadge("MP3", MaterialTheme.colorScheme.secondary)
                }
                Spacer(Modifier.height(2.dp))
                Text(
                    text = result.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.height(2.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        text = formatSize(result.size),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = "↑${result.seeders}",
                        style = MaterialTheme.typography.bodySmall,
                        color = if (result.seeders > 5) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    result.sources?.firstOrNull()?.let { src ->
                        Text(
                            text = src,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            // Stream button / state
            when (streamState) {
                is StreamState.Idle -> {
                    IconButton(onClick = onStream) {
                        Icon(
                            Icons.Default.PlayArrow,
                            "Stream best track",
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                    IconButton(onClick = onStreamAlbum) {
                        Icon(
                            Icons.Default.Album,
                            "Stream full album",
                            tint = MaterialTheme.colorScheme.secondary,
                        )
                    }
                }
                is StreamState.Queuing, is StreamState.Preparing -> {
                    IconButton(onClick = onCancel) {
                        Icon(Icons.Default.Close, "Cancel", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                is StreamState.Ready -> {
                    if (isDownloading) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                    } else {
                        IconButton(onClick = onDownload) {
                            Icon(Icons.Default.Download, "Download", tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                    TextButton(onClick = onNowPlaying) { Text("Playing") }
                }
                is StreamState.ReadyAlbum -> {
                    TextButton(onClick = onNowPlaying) {
                        Text("${streamState.tracks.size} tracks")
                    }
                }
                is StreamState.Error -> {
                    TextButton(onClick = onStream) {
                        Text("Retry", color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }

        // Inline status for the item currently streaming
        if (isStreaming) {
            Spacer(Modifier.height(6.dp))
            when (streamState) {
                is StreamState.Queuing -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(8.dp))
                        Text("Adding to TorBox…", style = MaterialTheme.typography.bodySmall)
                    }
                }
                is StreamState.Preparing -> {
                    Column {
                        LinearProgressIndicator(
                            progress = { streamState.progress },
                            modifier = Modifier.fillMaxWidth(),
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Text(
                            "Preparing: ${(streamState.progress * 100).toInt()}%",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                is StreamState.Error -> {
                    Text(
                        streamState.message,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
                else -> {}
            }
        }
    }
}

@Composable
private fun FormatBadge(label: String, color: androidx.compose.ui.graphics.Color) {
    Surface(
        color = color.copy(alpha = 0.15f),
        shape = MaterialTheme.shapes.extraSmall,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = color,
            modifier = Modifier.padding(horizontal = 5.dp, vertical = 1.dp),
        )
    }
}

private fun formatSize(bytes: Long): String {
    if (bytes <= 0) return "?"
    val gb = bytes / 1_073_741_824.0
    val mb = bytes / 1_048_576.0
    return when {
        gb >= 1.0 -> "%.1f GB".format(gb)
        mb >= 1.0 -> "%.0f MB".format(mb)
        else -> "${bytes / 1024} KB"
    }
}
