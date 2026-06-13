package com.debridmusic.app.ui.artist

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.debridmusic.app.ui.theme.rememberDominantColor
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import com.debridmusic.app.domain.model.Album
import com.debridmusic.app.ui.components.AlbumCard
import com.debridmusic.app.ui.components.MiniPlayer
import com.debridmusic.app.ui.components.TrackItem

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArtistDetailScreen(
    onBack: () -> Unit,
    onAlbumClick: (Long) -> Unit,
    onNowPlayingClick: () -> Unit,
    viewModel: ArtistDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val currentTrack by viewModel.playerController.currentTrack.collectAsStateWithLifecycle()
    val isPlaying by viewModel.playerController.isPlaying.collectAsStateWithLifecycle()
    val positionMs by viewModel.playerController.positionMs.collectAsStateWithLifecycle()
    val durationMs by viewModel.playerController.durationMs.collectAsStateWithLifecycle()

    val progress = if (durationMs > 0) positionMs.toFloat() / durationMs else 0f
    val accent by rememberDominantColor(
        state.artist?.imageUri ?: state.artist?.bannerUri,
        MaterialTheme.colorScheme.primary,
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(state.artist?.name ?: "") },
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
            // Artist hero — full-bleed fan-art banner with a dynamic colour scrim
            item {
                val backdrop = state.artist?.bannerUri ?: state.artist?.imageUri
                Box(modifier = Modifier.fillMaxWidth().height(320.dp)) {
                    if (backdrop != null) {
                        AsyncImage(
                            model = backdrop,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize(),
                        )
                    } else {
                        Box(Modifier.fillMaxSize().background(accent.copy(alpha = 0.35f)))
                    }
                    // Dynamic gradient: fades the artwork into a tinted scrim, then bg
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(
                                Brush.verticalGradient(
                                    0.0f to Color.Transparent,
                                    0.45f to accent.copy(alpha = 0.25f),
                                    0.8f to MaterialTheme.colorScheme.background.copy(alpha = 0.85f),
                                    1.0f to MaterialTheme.colorScheme.background,
                                )
                            )
                    )
                    Column(
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(20.dp),
                    ) {
                        Text(
                            text = state.artist?.name ?: "",
                            style = MaterialTheme.typography.displaySmall,
                            fontWeight = FontWeight.Bold,
                            color = Color.White,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Spacer(Modifier.height(4.dp))
                        Text(
                            text = buildString {
                                state.artist?.genre?.takeIf { it.isNotBlank() }?.let { append(it); append("  •  ") }
                                append("${state.albums.size} albums  •  ${state.tracks.size} tracks")
                            },
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color.White.copy(alpha = 0.85f),
                        )
                    }
                }
            }

            // Play button (tinted with the artwork's accent colour)
            item {
                Row(modifier = Modifier.padding(16.dp)) {
                    Button(
                        onClick = {
                            viewModel.playAll()
                            onNowPlayingClick()
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = accent, contentColor = Color.White),
                    ) {
                        Icon(Icons.Default.PlayArrow, null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("Play all")
                    }
                }
            }

            // Biography
            state.artist?.biography?.let { bio ->
                item {
                    Column(
                        modifier = Modifier
                            .padding(horizontal = 16.dp)
                            .animateContentSize(),
                    ) {
                        Text(
                            text = "About",
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(bottom = 8.dp),
                        )
                        Text(
                            text = bio,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = if (state.showFullBio) Int.MAX_VALUE else 4,
                            overflow = TextOverflow.Ellipsis,
                        )
                        TextButton(onClick = viewModel::toggleBio) {
                            Text(if (state.showFullBio) "Show less" else "Read more")
                        }
                    }
                }
            }

            // Discography
            if (state.albums.isNotEmpty()) {
                item {
                    Text(
                        text = "Discography",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 8.dp),
                    )
                }
                item {
                    LazyRow(
                        contentPadding = PaddingValues(horizontal = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        items(state.albums, key = { it.id }) { album ->
                            AlbumCard(
                                album = album,
                                onAlbumClick = { onAlbumClick(it.id) },
                                modifier = Modifier.width(148.dp),
                            )
                        }
                    }
                }
            }

            // Top tracks
            if (state.tracks.isNotEmpty()) {
                item {
                    Text(
                        text = "Tracks",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
                    )
                }
                itemsIndexed(state.tracks, key = { _, t -> t.id }) { _, track ->
                    TrackItem(
                        track = track,
                        isPlaying = isPlaying && track.id == currentTrack?.id,
                        onTrackClick = { t ->
                            viewModel.playTrack(t)
                            onNowPlayingClick()
                        },
                        showAlbum = true,
                    )
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                        modifier = Modifier.padding(start = 76.dp),
                    )
                }
            }

            item { Spacer(Modifier.height(16.dp)) }
        }
    }

    if (state.editorOpen) {
        MetadataEditorDialog(
            title = "Artiestmetadata zoeken",
            initialQuery = state.artist?.name.orEmpty(),
            searching = state.searching,
            candidates = state.candidates.map {
                MetadataCandidate(
                    title = it.name,
                    subtitle = "",
                    thumbnailUrl = it.imageUrl,
                    source = it.source,
                )
            },
            onSearch = viewModel::searchMetadata,
            onPick = { idx -> viewModel.applyMatch(state.candidates[idx]) },
            onDismiss = viewModel::closeEditor,
        )
    }
}
