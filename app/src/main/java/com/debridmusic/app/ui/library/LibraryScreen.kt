package com.debridmusic.app.ui.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.PlaylistPlay
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.debridmusic.app.domain.model.Album
import com.debridmusic.app.ui.components.AddToPlaylistDialog
import com.debridmusic.app.ui.components.AlbumArtwork
import com.debridmusic.app.ui.components.AlbumCard
import com.debridmusic.app.ui.components.MiniPlayer
import com.debridmusic.app.ui.components.TrackItem
import com.debridmusic.app.ui.playlist.PlaylistsScreen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(
    onTrackClick: () -> Unit,
    onAlbumClick: (Long) -> Unit,
    onArtistClick: (Long) -> Unit,
    onSettingsClick: () -> Unit,
    onDownloadsClick: () -> Unit = {},
    onStreamOnlineClick: () -> Unit = {},
    onSoulseekClick: () -> Unit = {},
    onPlaylistClick: (Long) -> Unit = {},
    viewModel: LibraryViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val uriHandler = LocalUriHandler.current
    val currentTrack by viewModel.playerController.currentTrack.collectAsStateWithLifecycle()
    val isPlaying by viewModel.playerController.isPlaying.collectAsStateWithLifecycle()
    val positionMs by viewModel.playerController.positionMs.collectAsStateWithLifecycle()
    val durationMs by viewModel.playerController.durationMs.collectAsStateWithLifecycle()

    val progress = if (durationMs > 0) positionMs.toFloat() / durationMs.toFloat() else 0f

    LaunchedEffect(Unit) { viewModel.playerController.connect() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    if (state.isSearching) {
                        TextField(
                            value = state.searchQuery,
                            onValueChange = viewModel::setSearchQuery,
                            placeholder = { Text("Search tracks, albums, artists…") },
                            singleLine = true,
                            colors = TextFieldDefaults.colors(
                                focusedContainerColor = MaterialTheme.colorScheme.surface,
                                unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                            ),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    } else {
                        Text("Library")
                    }
                },
                actions = {
                    if (state.isSearching) {
                        IconButton(onClick = viewModel::clearSearch) {
                            Icon(Icons.Default.Close, "Clear search")
                        }
                    } else {
                        IconButton(onClick = { viewModel.setSearchQuery(" ") }) {
                            Icon(Icons.Default.Search, "Search")
                        }
                        IconButton(
                            onClick = viewModel::scanLocalMedia,
                            enabled = !state.isScanning,
                        ) {
                            if (state.isScanning) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(20.dp),
                                    strokeWidth = 2.dp,
                                )
                            } else {
                                Icon(Icons.Default.Sync, "Scan music")
                            }
                        }
                        IconButton(onClick = onStreamOnlineClick) {
                            Icon(Icons.Default.CloudDownload, "Stream online")
                        }
                        IconButton(onClick = onSoulseekClick) {
                            Icon(Icons.Default.People, "Soulseek P2P")
                        }
                        IconButton(onClick = onDownloadsClick) {
                            Icon(Icons.Default.Download, "Downloads")
                        }
                        IconButton(onClick = onSettingsClick) {
                            Icon(Icons.Default.Settings, "Settings")
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
                    onClick = onTrackClick,
                )
            }
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {

            state.scanMessage?.let { msg ->
                Snackbar(modifier = Modifier.padding(16.dp)) { Text(msg) }
            }

            if (!state.isSearching) {
                TabRow(
                    selectedTabIndex = state.tab.ordinal,
                    containerColor = MaterialTheme.colorScheme.surface,
                ) {
                    Tab(
                        selected = state.tab == LibraryTab.TRACKS,
                        onClick = { viewModel.setTab(LibraryTab.TRACKS) },
                        text = { Text("Tracks") },
                    )
                    Tab(
                        selected = state.tab == LibraryTab.ALBUMS,
                        onClick = { viewModel.setTab(LibraryTab.ALBUMS) },
                        text = { Text("Albums") },
                    )
                    Tab(
                        selected = state.tab == LibraryTab.ARTISTS,
                        onClick = { viewModel.setTab(LibraryTab.ARTISTS) },
                        text = { Text("Artists") },
                    )
                    Tab(
                        selected = state.tab == LibraryTab.PLAYLISTS,
                        onClick = { viewModel.setTab(LibraryTab.PLAYLISTS) },
                        text = { Text("Playlists") },
                    )
                    Tab(
                        selected = state.tab == LibraryTab.DISCOGS,
                        onClick = { viewModel.setTab(LibraryTab.DISCOGS) },
                        text = { Text("Discogs") },
                    )
                }
            }

            when {
                state.isSearching -> {
                    TrackList(
                        tracks = state.searchResults,
                        currentTrackId = currentTrack?.id,
                        isPlaying = isPlaying,
                        onTrackClick = { track ->
                            viewModel.playTrack(track, state.searchResults)
                            onTrackClick()
                        },
                        onAddToPlaylist = { track -> viewModel.showAddToPlaylist(track) },
                    )
                }

                state.tab == LibraryTab.TRACKS -> {
                    if (state.tracks.isEmpty()) {
                        EmptyState(
                            message = if (state.totalTracks == 0)
                                "No tracks found.\nTap the scan button to import local music."
                            else "No tracks."
                        )
                    } else {
                        TrackList(
                            tracks = state.tracks,
                            currentTrackId = currentTrack?.id,
                            isPlaying = isPlaying,
                            onTrackClick = { track ->
                                viewModel.playTrack(track, state.tracks)
                                onTrackClick()
                            },
                            onAddToPlaylist = { track -> viewModel.showAddToPlaylist(track) },
                        )
                    }
                }

                state.tab == LibraryTab.ALBUMS -> {
                    if (state.albums.isEmpty()) {
                        EmptyState(message = "No albums found.")
                    } else {
                        AlbumGrid(
                            albums = state.albums,
                            onAlbumClick = { album -> onAlbumClick(album.id) },
                        )
                    }
                }

                state.tab == LibraryTab.ARTISTS -> {
                    if (state.artists.isEmpty()) {
                        EmptyState(message = "No artists found.")
                    } else {
                        ArtistList(
                            artists = state.artists,
                            onArtistClick = { artist -> onArtistClick(artist.id) },
                        )
                    }
                }

                state.tab == LibraryTab.PLAYLISTS -> {
                    PlaylistsScreen(
                        playlists = state.playlists,
                        showCreateDialog = state.showCreatePlaylist,
                        newPlaylistName = state.newPlaylistName,
                        onNewNameChange = viewModel::setNewPlaylistName,
                        onShowCreate = viewModel::showCreatePlaylist,
                        onHideCreate = viewModel::hideCreatePlaylist,
                        onCreate = viewModel::createPlaylist,
                        onDelete = viewModel::deletePlaylist,
                        onPlaylistClick = onPlaylistClick,
                    )
                }

                state.tab == LibraryTab.DISCOGS -> {
                    if (state.discogsCollection.isEmpty()) {
                        EmptyState(
                            message = "Nog geen Discogs-collectie.\nGa naar Instellingen → Discogs en tik op \"Sync Discogs-collectie\"."
                        )
                    } else {
                        AlbumGrid(
                            albums = state.discogsCollection,
                            // Discogs items aren't local albums; open the release on discogs.com.
                            onAlbumClick = { album ->
                                runCatching { uriHandler.openUri("https://www.discogs.com/release/${album.id}") }
                            },
                        )
                    }
                }
            }
        }
    }

    // Add-to-playlist dialog
    state.addToPlaylistTrack?.let { track ->
        AddToPlaylistDialog(
            playlists = state.playlists,
            onDismiss = viewModel::hideAddToPlaylist,
            onAddToPlaylist = viewModel::addTrackToPlaylist,
            onCreateAndAdd = viewModel::createPlaylistAndAddTrack,
        )
    }
}

@Composable
private fun TrackList(
    tracks: List<com.debridmusic.app.domain.model.Track>,
    currentTrackId: Long?,
    isPlaying: Boolean,
    onTrackClick: (com.debridmusic.app.domain.model.Track) -> Unit,
    onAddToPlaylist: (com.debridmusic.app.domain.model.Track) -> Unit,
) {
    LazyColumn(
        contentPadding = PaddingValues(vertical = 8.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        itemsIndexed(tracks, key = { _, t -> t.id }) { _, track ->
            TrackItem(
                track = track,
                isPlaying = isPlaying && track.id == currentTrackId,
                onTrackClick = onTrackClick,
                onMoreClick = onAddToPlaylist,
            )
            HorizontalDivider(
                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                modifier = Modifier.padding(start = 76.dp),
            )
        }
    }
}

@Composable
private fun AlbumGrid(
    albums: List<Album>,
    onAlbumClick: (Album) -> Unit,
) {
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        val rows = albums.chunked(2)
        items(rows) { row ->
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                row.forEach { album ->
                    AlbumCard(
                        album = album,
                        onAlbumClick = onAlbumClick,
                        modifier = Modifier.weight(1f),
                    )
                }
                if (row.size == 1) Spacer(modifier = Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun ArtistList(
    artists: List<com.debridmusic.app.domain.model.Artist>,
    onArtistClick: (com.debridmusic.app.domain.model.Artist) -> Unit,
) {
    LazyColumn(
        contentPadding = PaddingValues(vertical = 8.dp),
        modifier = Modifier.fillMaxSize(),
    ) {
        items(artists, key = { it.id }) { artist ->
            ListItem(
                headlineContent = { Text(artist.name) },
                supportingContent = {
                    Text(
                        text = "${artist.albumCount} albums",
                        style = MaterialTheme.typography.bodySmall,
                    )
                },
                leadingContent = {
                    AlbumArtwork(
                        uri = artist.imageUri,
                        size = 48.dp,
                        cornerRadius = 24.dp,
                    )
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onArtistClick(artist) },
            )
            HorizontalDivider(
                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                modifier = Modifier.padding(start = 76.dp),
            )
        }
    }
}

@Composable
private fun EmptyState(message: String) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier.fillMaxSize().padding(32.dp),
    ) {
        Text(
            text = message,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
