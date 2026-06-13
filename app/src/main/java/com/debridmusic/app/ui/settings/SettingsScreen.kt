package com.debridmusic.app.ui.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Equalizer
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    viewModel: SettingsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var showLastFmKey by remember { mutableStateOf(false) }
    var showTorBoxKey by remember { mutableStateOf(false) }
    var showLastFmSecret by remember { mutableStateOf(false) }
    var showLastFmPassword by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, "Back") }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {

            // ── TorBox ──────────────────────────────────────────────────────
            SectionHeader("TorBox")

            Text(
                text = "Required to search and stream music via debrid.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            OutlinedTextField(
                value = state.torBoxApiKey,
                onValueChange = viewModel::setTorBoxApiKey,
                label = { Text("TorBox API key") },
                placeholder = { Text("Get your key at torbox.app") },
                singleLine = true,
                visualTransformation = if (showTorBoxKey) VisualTransformation.None
                else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                trailingIcon = {
                    IconButton(onClick = { showTorBoxKey = !showTorBoxKey }) {
                        Icon(
                            if (showTorBoxKey) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            null,
                        )
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            )

            state.torBoxUser?.let { user ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.CheckCircle, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(
                        text = "${user.email ?: "Connected"} · ${if (user.isSubscribed) "Premium" else "Free"}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
            state.torBoxError?.let { err ->
                Text(err, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = { viewModel.saveKeys(); viewModel.validateTorBoxKey() },
                    enabled = state.torBoxApiKey.isNotBlank() && !state.torBoxValidating,
                    modifier = Modifier.weight(1f),
                ) {
                    if (state.torBoxValidating) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                        Spacer(Modifier.width(8.dp))
                    }
                    Text("Save & verify")
                }
            }

            HorizontalDivider()

            // ── Soulseek ─────────────────────────────────────────────────────
            SectionHeader("Soulseek P2P")

            Text(
                text = "Search and download music directly from other users via the Soulseek P2P network. Uses your own soulseek.net account.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            var showSlskPassword by remember { mutableStateOf(false) }

            OutlinedTextField(
                value = state.slskUsername,
                onValueChange = viewModel::setSlskUsername,
                label = { Text("Soulseek username") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            OutlinedTextField(
                value = state.slskPassword,
                onValueChange = viewModel::setSlskPassword,
                label = { Text("Soulseek password") },
                singleLine = true,
                visualTransformation = if (showSlskPassword) VisualTransformation.None else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                trailingIcon = {
                    IconButton(onClick = { showSlskPassword = !showSlskPassword }) {
                        Icon(if (showSlskPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility, null)
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            )

            if (state.slskLoggedIn) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.CheckCircle, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(
                        text = "Ingelogd als ${state.slskUsername}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
            state.slskError?.let { err ->
                Text(err, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }

            Button(
                onClick = viewModel::saveSlskCredentials,
                enabled = state.slskUsername.isNotBlank() && state.slskPassword.isNotBlank() && !state.slskVerifying,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (state.slskVerifying) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                    Spacer(Modifier.width(8.dp))
                    Text("Inloggen…")
                } else {
                    Text("Opslaan & inloggen")
                }
            }

            HorizontalDivider()

            // ── Metadata sources ─────────────────────────────────────────────
            SectionHeader("Metadata sources")

            OutlinedTextField(
                value = state.lastFmApiKey,
                onValueChange = viewModel::setLastFmApiKey,
                label = { Text("Last.fm API key") },
                placeholder = { Text("Get a free key at last.fm/api") },
                singleLine = true,
                visualTransformation = if (showLastFmKey) VisualTransformation.None else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                trailingIcon = {
                    IconButton(onClick = { showLastFmKey = !showLastFmKey }) {
                        Icon(if (showLastFmKey) Icons.Default.VisibilityOff else Icons.Default.Visibility, null)
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            )

            OutlinedTextField(
                value = state.discogsToken,
                onValueChange = viewModel::setDiscogsToken,
                label = { Text("Discogs token (optional)") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            Button(onClick = viewModel::saveKeys, modifier = Modifier.fillMaxWidth()) {
                Text("Save API keys")
            }

            HorizontalDivider()

            // ── Library enrichment ───────────────────────────────────────────
            SectionHeader("Library enrichment")

            Text(
                text = "Fetch album artwork, artist biographies, and MusicBrainz IDs for your entire local library.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            state.enrichProgress?.let { prog ->
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    LinearProgressIndicator(progress = { prog.fraction }, modifier = Modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.primary)
                    Text("${prog.current}/${prog.total} — ${prog.currentItem}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            state.enrichResult?.let { msg ->
                Text(msg, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
            }

            Button(onClick = viewModel::enrichLibrary, enabled = !state.isEnriching, modifier = Modifier.fillMaxWidth()) {
                if (state.isEnriching) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                    Spacer(Modifier.width(8.dp))
                    Text("Enriching…")
                } else {
                    Icon(Icons.Default.AutoAwesome, null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Enrich library metadata")
                }
            }

            HorizontalDivider()

            // ── Last.fm Scrobbling ────────────────────────────────────────────
            SectionHeader("Last.fm scrobbling")

            Text(
                text = "Automatically scrobble tracks you listen to. Requires a Last.fm account and API credentials.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            if (state.lastFmSessionKey.isNotBlank()) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Default.CheckCircle, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Ingelogd als ${state.lastFmUsername}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.weight(1f))
                    OutlinedButton(onClick = viewModel::logoutLastFm) { Text("Uitloggen") }
                }
            } else {
                OutlinedTextField(
                    value = state.lastFmUsername,
                    onValueChange = viewModel::setLastFmUsernameInput,
                    label = { Text("Last.fm username") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = state.lastFmPassword,
                    onValueChange = viewModel::setLastFmPassword,
                    label = { Text("Last.fm password") },
                    singleLine = true,
                    visualTransformation = if (showLastFmPassword) VisualTransformation.None else PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    trailingIcon = {
                        IconButton(onClick = { showLastFmPassword = !showLastFmPassword }) {
                            Icon(if (showLastFmPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility, null)
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = state.lastFmApiSecret,
                    onValueChange = viewModel::setLastFmApiSecret,
                    label = { Text("Last.fm API secret") },
                    singleLine = true,
                    visualTransformation = if (showLastFmSecret) VisualTransformation.None else PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    trailingIcon = {
                        IconButton(onClick = { showLastFmSecret = !showLastFmSecret }) {
                            Icon(if (showLastFmSecret) Icons.Default.VisibilityOff else Icons.Default.Visibility, null)
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                )
                state.lastFmLoginError?.let { err ->
                    Text(err, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                }
                Button(
                    onClick = viewModel::loginLastFm,
                    enabled = state.lastFmUsername.isNotBlank() && state.lastFmPassword.isNotBlank() &&
                            state.lastFmApiKey.isNotBlank() && state.lastFmApiSecret.isNotBlank() &&
                            !state.lastFmLoginLoading,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (state.lastFmLoginLoading) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                        Spacer(Modifier.width(8.dp))
                    }
                    Text("Inloggen bij Last.fm")
                }
            }

            HorizontalDivider()

            // ── EQ ────────────────────────────────────────────────────────────
            SectionHeader("Equalizer")

            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Default.Equalizer, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Text("EQ inschakelen", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                Switch(
                    checked = state.eqEnabled,
                    onCheckedChange = viewModel::setEqEnabled,
                )
            }

            if (state.eqEnabled) {
                val labels = viewModel.eqController.bandLabels
                state.eqBands.forEachIndexed { index, gain ->
                    Column {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(
                                text = if (index < labels.size) labels[index] else "Band ${index + 1}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.width(56.dp),
                            )
                            Slider(
                                value = gain,
                                onValueChange = { v -> viewModel.setEqBandGain(index, v) },
                                valueRange = state.eqRangeDb,
                                modifier = Modifier.weight(1f),
                                colors = SliderDefaults.colors(
                                    thumbColor = MaterialTheme.colorScheme.primary,
                                    activeTrackColor = MaterialTheme.colorScheme.primary,
                                ),
                            )
                            Text(
                                text = "%+.0f".format(gain),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.width(40.dp),
                            )
                        }
                    }
                }
            }

            HorizontalDivider()

            // ── Cross-fade ────────────────────────────────────────────────────
            SectionHeader("Cross-fade")

            val crossFadeSec = state.crossFadeDurationMs / 1000f
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = if (crossFadeSec == 0f) "Uit" else "%.0f sec".format(crossFadeSec),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.width(52.dp),
                )
                Slider(
                    value = crossFadeSec,
                    onValueChange = { v ->
                        viewModel.setCrossFadeDuration((v * 1000f).roundToInt())
                    },
                    valueRange = 0f..10f,
                    steps = 9,
                    modifier = Modifier.weight(1f),
                    colors = SliderDefaults.colors(
                        thumbColor = MaterialTheme.colorScheme.primary,
                        activeTrackColor = MaterialTheme.colorScheme.primary,
                    ),
                )
                Text(
                    text = "10 sec",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.width(44.dp),
                )
            }
            Text(
                text = "Fade glijdend over naar het volgende nummer.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(Modifier.height(32.dp))
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.primary,
    )
}
