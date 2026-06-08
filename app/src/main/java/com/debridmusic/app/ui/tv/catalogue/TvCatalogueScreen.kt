package com.debridmusic.app.ui.tv.catalogue

import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.input.key.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.debridmusic.app.data.remote.dto.TorBoxSearchResult
import com.debridmusic.app.torbox.StreamState
import com.debridmusic.app.ui.catalogue.CatalogueSearchViewModel

@Composable
fun TvCatalogueScreen(
    onBack: () -> Unit,
    onNowPlayingClick: () -> Unit,
    viewModel: CatalogueSearchViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val searchFocus = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        runCatching { searchFocus.requestFocus() }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
    ) {

        // ── Search bar ────────────────────────────────────────────────────
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface)
                .padding(horizontal = 24.dp, vertical = 12.dp),
        ) {
            TvSearchBackButton(onClick = onBack)
            Spacer(Modifier.width(16.dp))
            OutlinedTextField(
                value = state.query,
                onValueChange = viewModel::setQuery,
                placeholder = {
                    Text(
                        "Artiest · Album · Track …",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { viewModel.search() }),
                leadingIcon = {
                    Icon(Icons.Default.Search, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                },
                trailingIcon = {
                    if (state.query.isNotBlank()) {
                        IconButton(onClick = { viewModel.setQuery("") }) {
                            Icon(Icons.Default.Close, "Wis", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                    unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                    focusedTextColor = MaterialTheme.colorScheme.onSurface,
                    unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                    cursorColor = MaterialTheme.colorScheme.primary,
                ),
                shape = RoundedCornerShape(8.dp),
                modifier = Modifier
                    .weight(1f)
                    .focusRequester(searchFocus),
            )
            Spacer(Modifier.width(12.dp))
            Button(
                onClick = { viewModel.search() },
                enabled = state.query.isNotBlank() && !state.isSearching,
                modifier = Modifier.height(56.dp),
            ) {
                Text("Zoeken")
            }
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))

        // ── Body ──────────────────────────────────────────────────────────
        when {
            state.isSearching -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.height(16.dp))
                        Text(
                            "Zoeken via TorBox…",
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            state.searchError != null -> {
                Box(
                    Modifier.fillMaxSize().padding(48.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            "Zoekfout",
                            style = MaterialTheme.typography.headlineSmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                        Spacer(Modifier.height(8.dp))
                        Text(
                            state.searchError ?: "",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            state.results.isEmpty() && state.query.isBlank() -> {
                Box(
                    Modifier.fillMaxSize().padding(48.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            Icons.Default.Search,
                            null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                            modifier = Modifier.size(72.dp),
                        )
                        Spacer(Modifier.height(16.dp))
                        Text(
                            "Zoek naar artiest, album of nummer.\nTorBox streamt FLAC direct naar je toe.",
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            state.results.isEmpty() -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        "Geen resultaten",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            else -> {
                val listState = rememberLazyListState()
                LazyColumn(
                    state = listState,
                    contentPadding = PaddingValues(vertical = 12.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(state.results, key = { it.hash.ifBlank { it.name } }) { result ->
                        TvSearchResultRow(
                            result = result,
                            isStreaming = state.streamingId == result.hash,
                            streamState = if (state.streamingId == result.hash) state.streamState
                            else StreamState.Idle,
                            onStream = { viewModel.stream(result) },
                            onCancel = { viewModel.cancelStream() },
                            onNowPlaying = onNowPlayingClick,
                        )
                        HorizontalDivider(
                            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                            modifier = Modifier.padding(horizontal = 24.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TvSearchResultRow(
    result: TorBoxSearchResult,
    isStreaming: Boolean,
    streamState: StreamState,
    onStream: () -> Unit,
    onCancel: () -> Unit,
    onNowPlaying: () -> Unit,
) {
    var isFocused by remember { mutableStateOf(false) }
    val isFlac = result.name.contains("flac", ignoreCase = true)
    val isMp3 = result.name.contains("mp3", ignoreCase = true) ||
            result.name.contains("320", ignoreCase = false)

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .background(
                if (isFocused) MaterialTheme.colorScheme.surfaceVariant
                else MaterialTheme.colorScheme.background
            )
            .onFocusChanged { isFocused = it.isFocused }
            .focusable()
            .onKeyEvent { event ->
                if (event.key == Key.DirectionCenter && event.type == KeyEventType.KeyUp) {
                    when (streamState) {
                        is StreamState.Idle, is StreamState.Error -> onStream()
                        is StreamState.Ready, is StreamState.ReadyAlbum, is StreamState.TrackList -> onNowPlaying()
                        else -> onCancel()
                    }
                    true
                } else false
            }
            .padding(horizontal = 24.dp, vertical = 14.dp),
    ) {
        // Format badge column
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.width(56.dp),
        ) {
            when {
                isFlac -> FormatChip("FLAC", MaterialTheme.colorScheme.primary)
                isMp3 -> FormatChip("MP3", MaterialTheme.colorScheme.secondary)
                else -> Spacer(Modifier.height(20.dp))
            }
        }
        Spacer(Modifier.width(16.dp))

        // Name + meta
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = result.name,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(4.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(
                    text = formatBytes(result.size),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = "↑ ${result.seeders} seeders",
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

            // Inline stream progress
            if (isStreaming) {
                Spacer(Modifier.height(8.dp))
                when (streamState) {
                    is StreamState.Queuing -> {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(8.dp))
                            Text(
                                "Toevoegen aan TorBox…",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    is StreamState.Preparing -> {
                        Column {
                            LinearProgressIndicator(
                                progress = { streamState.progress },
                                modifier = Modifier.fillMaxWidth().height(3.dp),
                                color = MaterialTheme.colorScheme.primary,
                                trackColor = MaterialTheme.colorScheme.outline,
                            )
                            Spacer(Modifier.height(4.dp))
                            Text(
                                "Voorbereiden: ${(streamState.progress * 100).toInt()}%",
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
        Spacer(Modifier.width(16.dp))

        // Action button
        when (streamState) {
            is StreamState.Idle -> {
                FilledIconButton(
                    onClick = onStream,
                    modifier = Modifier.size(48.dp),
                ) {
                    Icon(Icons.Default.PlayArrow, "Streamen", modifier = Modifier.size(24.dp))
                }
            }
            is StreamState.Queuing, is StreamState.Preparing -> {
                IconButton(onClick = onCancel, modifier = Modifier.size(48.dp)) {
                    Icon(
                        Icons.Default.Close,
                        "Annuleren",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            is StreamState.Ready -> {
                Button(onClick = onNowPlaying, modifier = Modifier.height(48.dp)) {
                    Text("Speelt")
                }
            }
            is StreamState.ReadyAlbum -> {
                Button(onClick = onNowPlaying, modifier = Modifier.height(48.dp)) {
                    Text("${streamState.tracks.size} tracks")
                }
            }
            is StreamState.TrackList -> {
                Button(onClick = onNowPlaying, modifier = Modifier.height(48.dp)) {
                    Text("${streamState.files.size} tracks")
                }
            }
            is StreamState.Error -> {
                OutlinedButton(onClick = onStream, modifier = Modifier.height(48.dp)) {
                    Text("Opnieuw", color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}

@Composable
private fun TvSearchBackButton(onClick: () -> Unit) {
    var isFocused by remember { mutableStateOf(false) }
    Surface(
        onClick = onClick,
        color = if (isFocused) MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.surface,
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier
            .size(48.dp)
            .onFocusChanged { isFocused = it.isFocused }
            .focusable(),
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
            Icon(
                Icons.Default.ArrowBack,
                "Terug",
                tint = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.size(24.dp),
            )
        }
    }
}

@Composable
private fun FormatChip(label: String, color: androidx.compose.ui.graphics.Color) {
    Surface(
        color = color.copy(alpha = 0.15f),
        shape = MaterialTheme.shapes.extraSmall,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = color,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
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
