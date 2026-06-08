package com.debridmusic.app.ui.playlist

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PlaylistPlay
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.debridmusic.app.domain.model.Playlist

@Composable
fun PlaylistsScreen(
    playlists: List<Playlist>,
    showCreateDialog: Boolean,
    newPlaylistName: String,
    onNewNameChange: (String) -> Unit,
    onShowCreate: () -> Unit,
    onHideCreate: () -> Unit,
    onCreate: () -> Unit,
    onDelete: (Long) -> Unit,
    onPlaylistClick: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.fillMaxSize()) {
        if (playlists.isEmpty()) {
            Column(
                modifier = Modifier.align(Alignment.Center).padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(
                    Icons.Default.PlaylistPlay,
                    null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                    modifier = Modifier.size(64.dp),
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    "No playlists yet.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(16.dp))
                Button(onClick = onShowCreate) { Text("Create playlist") }
            }
        } else {
            LazyColumn(
                contentPadding = PaddingValues(vertical = 8.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                items(playlists, key = { it.id }) { playlist ->
                    ListItem(
                        headlineContent = { Text(playlist.name) },
                        supportingContent = {
                            Text(
                                "${playlist.trackCount} tracks",
                                style = MaterialTheme.typography.bodySmall,
                            )
                        },
                        leadingContent = {
                            Icon(
                                Icons.Default.PlaylistPlay,
                                null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(40.dp),
                            )
                        },
                        trailingContent = {
                            IconButton(onClick = { onDelete(playlist.id) }) {
                                Icon(
                                    Icons.Default.Delete,
                                    "Delete",
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ListItemDefaults.colors(
                            containerColor = MaterialTheme.colorScheme.background,
                        ),
                    )
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                        modifier = Modifier.padding(start = 72.dp),
                    )
                }
            }
        }

        FloatingActionButton(
            onClick = onShowCreate,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(16.dp),
            containerColor = MaterialTheme.colorScheme.primary,
        ) {
            Icon(Icons.Default.Add, "New playlist")
        }
    }

    if (showCreateDialog) {
        AlertDialog(
            onDismissRequest = onHideCreate,
            title = { Text("New playlist") },
            text = {
                OutlinedTextField(
                    value = newPlaylistName,
                    onValueChange = onNewNameChange,
                    label = { Text("Playlist name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            },
            confirmButton = {
                Button(
                    onClick = onCreate,
                    enabled = newPlaylistName.isNotBlank(),
                ) { Text("Create") }
            },
            dismissButton = {
                TextButton(onClick = onHideCreate) { Text("Cancel") }
            },
        )
    }
}
