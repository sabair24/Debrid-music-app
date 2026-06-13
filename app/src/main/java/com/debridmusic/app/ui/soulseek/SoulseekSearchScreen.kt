package com.debridmusic.app.ui.soulseek

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Download
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
import com.debridmusic.app.soulseek.SoulseekFile
import com.debridmusic.app.ui.components.MiniPlayer

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SoulseekSearchScreen(
    onBack: () -> Unit,
    onNowPlayingClick: () -> Unit,
    viewModel: SoulseekSearchViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val currentTrack by viewModel.playerController.currentTrack.collectAsStateWithLifecycle()
    val isPlaying by viewModel.playerController.isPlaying.collectAsStateWithLifecycle()
    val positionMs by viewModel.playerController.positionMs.collectAsStateWithLifecycle()
    val durationMs by viewModel.playerController.durationMs.collectAsStateWithLifecycle()

    val focusRequester = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val progress = if (durationMs > 0) positionMs.toFloat() / durationMs else 0f
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(Unit) { runCatching { focusRequester.requestFocus() } }

    // Show queued/failed-download messages without wiping the results list.
    LaunchedEffect(state.downloadInfo) {
        state.downloadInfo?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearDownloadInfo()
        }
    }

    // Navigate to now playing when download finishes and playback starts
    LaunchedEffect(currentTrack) {
        if (currentTrack != null && state.downloadingFile == null && state.downloadProgress == 0f) {
            // track started playing from this screen — don't auto-navigate, let user decide
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    TextField(
                        value = state.query,
                        onValueChange = viewModel::setQuery,
                        placeholder = { Text("Artiest · Album · Track…") },
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
                        modifier = Modifier.fillMaxWidth().focusRequester(focusRequester),
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, "Back") }
                },
                actions = {
                    if (state.query.isNotBlank()) {
                        IconButton(onClick = { viewModel.setQuery("") }) {
                            Icon(Icons.Default.Close, "Clear")
                        }
                    }
                    IconButton(onClick = { keyboard?.hide(); viewModel.search() }) {
                        Icon(Icons.Default.Search, "Search")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface),
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
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            when {
                state.isSearching -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                            Spacer(Modifier.height(12.dp))
                            Text(
                                "Zoeken op Soulseek… (5–10 sec)",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }

                state.searchError != null -> {
                    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("Fout", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.error)
                            Spacer(Modifier.height(8.dp))
                            Text(state.searchError ?: "", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }

                state.results.isEmpty() && state.query.isBlank() -> {
                    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                "Soulseek P2P",
                                style = MaterialTheme.typography.titleLarge,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.primary,
                            )
                            Spacer(Modifier.height(8.dp))
                            Text(
                                "Zoek muziek op het Soulseek-netwerk.\nResultaten komen binnen van andere gebruikers.\nZorg dat je inloggeggevens klopt in Instellingen.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }

                state.results.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text("Geen resultaten", style = MaterialTheme.typography.bodyMedium)
                    }
                }

                else -> {
                    LazyColumn(contentPadding = PaddingValues(vertical = 8.dp)) {
                        items(state.results, key = { "${it.username}:${it.filename}" }) { file ->
                            SlskFileRow(
                                file = file,
                                isDownloading = state.downloadingFile == file,
                                downloadProgress = if (state.downloadingFile == file) state.downloadProgress else 0f,
                                downloadStatus = if (state.downloadingFile == file) state.downloadStatus else null,
                                onDownload = { viewModel.downloadAndPlay(file) },
                                onCancel = viewModel::cancelDownload,
                            )
                            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SlskFileRow(
    file: SoulseekFile,
    isDownloading: Boolean,
    downloadProgress: Float,
    downloadStatus: String?,
    onDownload: () -> Unit,
    onCancel: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                // Format badge
                if (file.isFlac) {
                    SlskFormatBadge("FLAC", MaterialTheme.colorScheme.primary)
                } else if (file.extension == "mp3") {
                    SlskFormatBadge("MP3", MaterialTheme.colorScheme.secondary)
                }

                Text(
                    text = file.displayName,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )

                Spacer(Modifier.height(2.dp))

                // Meta row
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = formatBytes(file.size),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    file.bitrate?.let {
                        Text(
                            text = "${it}kbps${if (file.isVbr) " VBR" else ""}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    file.durationSec?.let {
                        Text(
                            text = formatDuration(it),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Text(
                        text = file.username,
                        style = MaterialTheme.typography.bodySmall,
                        color = if (file.freeSlots) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Spacer(Modifier.width(8.dp))

            if (isDownloading) {
                IconButton(onClick = onCancel) {
                    Box(contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(
                            progress = { downloadProgress },
                            modifier = Modifier.size(32.dp),
                            strokeWidth = 3.dp,
                        )
                    }
                }
            } else {
                IconButton(onClick = onDownload) {
                    Icon(Icons.Default.Download, "Download & play", tint = MaterialTheme.colorScheme.primary)
                }
            }
        }

        if (isDownloading) {
            Spacer(Modifier.height(4.dp))
            if (downloadProgress > 0f) {
                LinearProgressIndicator(
                    progress = { downloadProgress },
                    modifier = Modifier.fillMaxWidth(),
                    color = MaterialTheme.colorScheme.primary,
                )
                Text(
                    "${(downloadProgress * 100).toInt()}%  ·  ${formatBytes((file.size * downloadProgress).toLong())} / ${formatBytes(file.size)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.primary)
                Text(
                    downloadStatus ?: "Bezig…",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun SlskFormatBadge(label: String, color: androidx.compose.ui.graphics.Color) {
    Surface(color = color.copy(alpha = 0.15f), shape = MaterialTheme.shapes.extraSmall) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = color,
            modifier = Modifier.padding(horizontal = 5.dp, vertical = 1.dp),
        )
    }
}

private fun formatBytes(bytes: Long): String {
    if (bytes <= 0) return "?"
    val gb = bytes / 1_073_741_824.0
    val mb = bytes / 1_048_576.0
    return when {
        gb >= 1.0 -> "%.1f GB".format(gb)
        mb >= 1.0 -> "%.0f MB".format(mb)
        else -> "${bytes / 1024} KB"
    }
}

private fun formatDuration(sec: Int): String {
    val m = sec / 60; val s = sec % 60
    return "%d:%02d".format(m, s)
}
