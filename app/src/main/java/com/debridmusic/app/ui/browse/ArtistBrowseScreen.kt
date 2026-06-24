package com.debridmusic.app.ui.browse

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
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
fun ArtistBrowseScreen(
    onBack: () -> Unit,
    onAlbumClick: (Long) -> Unit,
    onNowPlayingClick: () -> Unit,
    viewModel: ArtistBrowseViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val currentTrack by viewModel.playerController.currentTrack.collectAsStateWithLifecycle()
    val isPlaying by viewModel.playerController.isPlaying.collectAsStateWithLifecycle()
    val positionMs by viewModel.playerController.positionMs.collectAsStateWithLifecycle()
    val durationMs by viewModel.playerController.durationMs.collectAsStateWithLifecycle()

    val disco = state.discography
    val title = disco?.artist?.name ?: "Artiest"

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
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
            disco == null -> Box(Modifier.fillMaxSize().padding(padding), Alignment.Center) { Text("Niets gevonden") }
            else -> LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
                item {
                    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        AlbumArtwork(uri = disco.artist?.imageUri, size = 96.dp, cornerRadius = 48.dp)
                        Spacer(Modifier.width(16.dp))
                        Text(title, style = MaterialTheme.typography.headlineSmall)
                    }
                }
                state.statusMessage?.let { msg ->
                    item {
                        Text(
                            msg,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                        )
                    }
                }

                if (disco.topTracks.isNotEmpty()) {
                    item { SectionTitle("Top songs") }
                    items(disco.topTracks.take(10)) { track ->
                        BrowseTrackRow(track.position.takeIf { it > 0 } ?: 1, track) { viewModel.playSong(track) }
                    }
                }
                if (disco.albums.isNotEmpty()) {
                    item { SectionTitle("Albums") }
                    item {
                        LazyRow(contentPadding = PaddingValues(horizontal = 12.dp)) {
                            items(disco.albums) { album -> BrowseAlbumCard(album) { onAlbumClick(album.id) } }
                        }
                    }
                }
                if (disco.singles.isNotEmpty()) {
                    item { SectionTitle("Singles & EP's") }
                    item {
                        LazyRow(contentPadding = PaddingValues(horizontal = 12.dp)) {
                            items(disco.singles) { album -> BrowseAlbumCard(album) { onAlbumClick(album.id) } }
                        }
                    }
                }
                item { Spacer(Modifier.height(16.dp)) }
            }
        }
    }
}
