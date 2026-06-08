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
import androidx.compose.material.icons.filled.PlayArrow
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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(state.artist?.name ?: "") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, "Back")
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
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // Artist hero image
            item {
                Box(modifier = Modifier.fillMaxWidth().height(240.dp)) {
                    state.artist?.imageUri?.let { uri ->
                        AsyncImage(
                            model = uri,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize(),
                        )
                    } ?: Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(MaterialTheme.colorScheme.surfaceVariant)
                    )
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(
                                Brush.verticalGradient(
                                    colors = listOf(
                                        MaterialTheme.colorScheme.background.copy(alpha = 0.1f),
                                        MaterialTheme.colorScheme.background,
                                    )
                                )
                            )
                    )
                    Column(
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(16.dp),
                    ) {
                        Text(
                            text = state.artist?.name ?: "",
                            style = MaterialTheme.typography.headlineLarge,
                            color = MaterialTheme.colorScheme.onBackground,
                        )
                        if (state.tracks.isNotEmpty()) {
                            Text(
                                text = "${state.tracks.size} tracks • ${state.albums.size} albums",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            // Play button
            item {
                Row(modifier = Modifier.padding(16.dp)) {
                    Button(onClick = {
                        viewModel.playAll()
                        onNowPlayingClick()
                    }) {
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
}
