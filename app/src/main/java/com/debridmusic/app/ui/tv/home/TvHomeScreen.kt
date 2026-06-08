package com.debridmusic.app.ui.tv.home

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import com.debridmusic.app.domain.model.Album
import com.debridmusic.app.ui.library.LibraryViewModel
import com.debridmusic.app.ui.tv.components.TvAlbumCard
import com.debridmusic.app.ui.tv.components.TvPlayerBar

@Composable
fun TvHomeScreen(
    onNowPlayingClick: () -> Unit,
    onCatalogueClick: () -> Unit,
    onAlbumClick: (Long) -> Unit,
    viewModel: LibraryViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val currentTrack by viewModel.playerController.currentTrack.collectAsStateWithLifecycle()
    val isPlaying by viewModel.playerController.isPlaying.collectAsStateWithLifecycle()
    val positionMs by viewModel.playerController.positionMs.collectAsStateWithLifecycle()
    val durationMs by viewModel.playerController.durationMs.collectAsStateWithLifecycle()

    val progress = if (durationMs > 0) positionMs.toFloat() / durationMs else 0f

    // Hero album is whichever album is focused in the first row, defaulting to first
    var heroAlbum by remember(state.albums) {
        mutableStateOf(state.albums.firstOrNull())
    }

    LaunchedEffect(Unit) { viewModel.playerController.connect() }

    Column(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        LazyColumn(
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(bottom = 16.dp),
        ) {

            // ── Hero banner ───────────────────────────────────────────────
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(340.dp),
                ) {
                    heroAlbum?.artworkUri?.let { uri ->
                        AsyncImage(
                            model = uri,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize(),
                        )
                    } ?: Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(MaterialTheme.colorScheme.surfaceVariant),
                    )
                    // Gradient overlay
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(
                                Brush.horizontalGradient(
                                    colors = listOf(
                                        MaterialTheme.colorScheme.background.copy(alpha = 0.95f),
                                        MaterialTheme.colorScheme.background.copy(alpha = 0.3f),
                                    )
                                )
                            ),
                    )
                    // Hero content
                    Column(
                        modifier = Modifier
                            .align(Alignment.CenterStart)
                            .padding(start = 40.dp, end = 280.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        heroAlbum?.let { album ->
                            Text(
                                text = "UITGELICHT",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.primary,
                                letterSpacing = androidx.compose.ui.unit.TextUnit(2f, androidx.compose.ui.unit.TextUnitType.Sp),
                            )
                            Text(
                                text = album.title,
                                style = MaterialTheme.typography.headlineLarge,
                                color = MaterialTheme.colorScheme.onBackground,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Text(
                                text = buildString {
                                    append(album.artistName)
                                    album.year?.let { append(" · $it") }
                                    if (album.trackCount > 0) append(" · ${album.trackCount} nummers")
                                },
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(Modifier.height(8.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Button(
                                    onClick = {
                                        viewModel.playTrack(
                                            state.tracks.firstOrNull { it.albumId == album.id }
                                                ?: return@Button,
                                            state.tracks.filter { it.albumId == album.id },
                                        )
                                        onNowPlayingClick()
                                    },
                                    modifier = Modifier.height(48.dp),
                                ) {
                                    Icon(Icons.Default.PlayArrow, null, modifier = Modifier.size(20.dp))
                                    Spacer(Modifier.width(8.dp))
                                    Text("Afspelen")
                                }
                                OutlinedButton(
                                    onClick = { onAlbumClick(album.id) },
                                    modifier = Modifier.height(48.dp),
                                ) {
                                    Text("Album bekijken")
                                }
                            }
                        } ?: run {
                            // Empty library
                            Text(
                                text = "Welkom bij Debrid Music",
                                style = MaterialTheme.typography.headlineLarge,
                                color = MaterialTheme.colorScheme.onBackground,
                            )
                            Spacer(Modifier.height(8.dp))
                            Button(
                                onClick = viewModel::scanLocalMedia,
                                enabled = !state.isScanning,
                                modifier = Modifier.height(48.dp),
                            ) {
                                Icon(Icons.Default.Sync, null, modifier = Modifier.size(20.dp))
                                Spacer(Modifier.width(8.dp))
                                Text("Bibliotheek scannen")
                            }
                        }
                    }
                }
            }

            // ── Onlangs toegevoegd ────────────────────────────────────────
            if (state.albums.isNotEmpty()) {
                item {
                    TvSectionHeader("Onlangs toegevoegd")
                }
                item {
                    TvAlbumRow(
                        albums = state.albums,
                        onFocused = { album -> heroAlbum = album },
                        onAlbumClick = { album ->
                            viewModel.playTrack(
                                state.tracks.firstOrNull { it.albumId == album.id }
                                    ?: return@TvAlbumRow,
                                state.tracks.filter { it.albumId == album.id },
                            )
                            onNowPlayingClick()
                        },
                    )
                }
            }

            // ── Alle albums ───────────────────────────────────────────────
            if (state.albums.size > 6) {
                item { TvSectionHeader("Alle albums") }
                item {
                    TvAlbumRow(
                        albums = state.albums.sortedBy { it.title },
                        onFocused = { album -> heroAlbum = album },
                        onAlbumClick = { album -> onAlbumClick(album.id) },
                    )
                }
            }

            // ── Ontdekken / TorBox ────────────────────────────────────────
            item {
                TvSectionHeader("Online streamen")
                Spacer(Modifier.height(8.dp))
                Row(modifier = Modifier.padding(horizontal = 24.dp)) {
                    OutlinedButton(
                        onClick = onCatalogueClick,
                        modifier = Modifier.height(48.dp),
                    ) {
                        Text("Zoeken via TorBox →")
                    }
                }
                Spacer(Modifier.height(16.dp))
            }
        }

        // ── Persistent player bar ─────────────────────────────────────────
        TvPlayerBar(
            track = currentTrack,
            isPlaying = isPlaying,
            progress = progress,
            onPlayPause = { viewModel.playerController.togglePlayPause() },
            onPrevious = { viewModel.playerController.skipToPrevious() },
            onNext = { viewModel.playerController.skipToNext() },
            onBarClick = onNowPlayingClick,
        )
    }
}

@Composable
private fun TvSectionHeader(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.headlineSmall,
        color = MaterialTheme.colorScheme.onBackground,
        modifier = Modifier.padding(start = 24.dp, top = 24.dp, bottom = 12.dp),
    )
}

@Composable
private fun TvAlbumRow(
    albums: List<Album>,
    onFocused: (Album) -> Unit,
    onAlbumClick: (Album) -> Unit,
) {
    val listState = rememberLazyListState()
    LazyRow(
        state = listState,
        contentPadding = PaddingValues(horizontal = 24.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        items(albums, key = { it.id }) { album ->
            TvAlbumCard(
                album = album,
                onClick = { onAlbumClick(album) },
            )
        }
    }
}
