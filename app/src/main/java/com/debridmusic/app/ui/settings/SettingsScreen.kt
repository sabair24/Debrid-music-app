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
import androidx.compose.material.icons.filled.SystemUpdate
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
import com.debridmusic.app.BuildConfig
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

    val ctx = androidx.compose.ui.platform.LocalContext.current
    val folderPicker = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.OpenDocumentTree()
    ) { uri ->
        if (uri != null) {
            runCatching {
                ctx.contentResolver.takePersistableUriPermission(
                    uri,
                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            }
            viewModel.setDownloadTreeUri(uri.toString())
        }
    }

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

            // ── Storage ──────────────────────────────────────────────────────
            SectionHeader("Opslag")

            Text(
                text = "Downloads: ${formatStorageBytes(state.downloadsSizeBytes)}  ·  Cache: ${formatStorageBytes(state.cacheSizeBytes)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = "Downloadmap: ${state.downloadFolder}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // Max-size cap presets
            Text("Maximale download-grootte", style = MaterialTheme.typography.bodyMedium)
            val caps = listOf(
                0L to "Onbeperkt",
                2L * 1024 * 1024 * 1024 to "2 GB",
                4L * 1024 * 1024 * 1024 to "4 GB",
                8L * 1024 * 1024 * 1024 to "8 GB",
                16L * 1024 * 1024 * 1024 to "16 GB",
            )
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
                caps.forEach { (bytes, label) ->
                    FilterChip(
                        selected = state.maxDownloadBytes == bytes,
                        onClick = { viewModel.setMaxDownloadBytes(bytes) },
                        label = { Text(label, style = MaterialTheme.typography.labelSmall) },
                    )
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(onClick = { folderPicker.launch(null) }, modifier = Modifier.weight(1f)) {
                    Text("Kies map")
                }
                OutlinedButton(onClick = viewModel::clearCache, modifier = Modifier.weight(1f)) {
                    Text("Wis cache")
                }
            }
            OutlinedButton(onClick = viewModel::clearDownloads, modifier = Modifier.fillMaxWidth()) {
                Text("Wis alle downloads")
            }

            HorizontalDivider()

            // ── App updates ──────────────────────────────────────────────────
            SectionHeader("App-updates")

            Text(
                text = "Huidige versie: ${BuildConfig.VERSION_NAME} (build ${BuildConfig.BUILD_NUMBER})",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            if (state.updateAvailable) {
                Card(
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            "Nieuwe versie beschikbaar: ${state.updateVersion}",
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                        )
                        if (state.updateNotes.isNotBlank()) {
                            Text(
                                state.updateNotes.take(300),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                            )
                        }
                        if (state.updateDownloading) {
                            LinearProgressIndicator(
                                progress = { state.updateProgress },
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Text(
                                "Downloaden… ${(state.updateProgress * 100).roundToInt()}%",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onPrimaryContainer,
                            )
                        } else {
                            Button(onClick = viewModel::downloadUpdate, modifier = Modifier.fillMaxWidth()) {
                                Icon(Icons.Default.SystemUpdate, null, modifier = Modifier.size(16.dp))
                                Spacer(Modifier.width(8.dp))
                                Text("Nu updaten")
                            }
                        }
                    }
                }
            } else {
                OutlinedButton(
                    onClick = { viewModel.checkForUpdate() },
                    enabled = !state.updateChecking,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (state.updateChecking) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(8.dp))
                        Text("Controleren…")
                    } else {
                        Icon(Icons.Default.SystemUpdate, null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("Controleer op updates")
                    }
                }
                if (state.updateUpToDate) {
                    Text(
                        "Je hebt de nieuwste versie.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
            state.updateError?.let { err ->
                Text(err, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }

            HorizontalDivider()

            // ── Tidal ─────────────────────────────────────────────────────────
            SectionHeader("Tidal")
            Text(
                text = "Log in met je eigen Tidal-account via de officiële Tidal-SDK. Vereist een gratis Client ID van developer.tidal.com.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            if (state.tidalLoggedIn) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.CheckCircle, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Ingelogd bij Tidal", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.weight(1f))
                    OutlinedButton(onClick = viewModel::tidalLogout) { Text("Uitloggen") }
                }
            } else {
                OutlinedTextField(
                    value = state.tidalClientId,
                    onValueChange = viewModel::setTidalClientId,
                    label = { Text("Tidal Client ID") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = state.tidalClientSecret,
                    onValueChange = viewModel::setTidalClientSecret,
                    label = { Text("Tidal Client Secret") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth(),
                )

                if (state.tidalUserCode != null) {
                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer), modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("1. Open de link en log in bij Tidal", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onPrimaryContainer)
                            Text("Code: ${state.tidalUserCode}", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onPrimaryContainer)
                            val url = state.tidalVerifyUrl
                            if (url != null) {
                                Text(url, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onPrimaryContainer)
                                OutlinedButton(onClick = {
                                    runCatching {
                                        val u = if (url.startsWith("http")) url else "https://$url"
                                        ctx.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(u)))
                                    }
                                }) { Text("Open Tidal-login") }
                            }
                            Button(onClick = viewModel::completeTidalLogin, enabled = !state.tidalBusy, modifier = Modifier.fillMaxWidth()) {
                                if (state.tidalBusy) { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary); Spacer(Modifier.width(8.dp)) }
                                Text("2. Ik heb ingelogd → voltooien")
                            }
                        }
                    }
                } else {
                    Button(
                        onClick = viewModel::startTidalLogin,
                        enabled = state.tidalClientId.isNotBlank() && !state.tidalBusy,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        if (state.tidalBusy) { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary); Spacer(Modifier.width(8.dp)) }
                        Text("Log in bij Tidal")
                    }
                }
                state.tidalError?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error) }
            }

            HorizontalDivider()

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

            // ── RuTracker ─────────────────────────────────────────────────────
            SectionHeader("RuTracker (zoekbron)")
            Text(
                text = "Voeg RuTracker toe als torrent-bron (veel lossless/FLAC). Vereist je eigen RuTracker-login. Kan onbetrouwbaar zijn (CAPTCHA bij eerste login, ISP-blokkade).",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            var showRuPass by remember { mutableStateOf(false) }
            OutlinedTextField(
                value = state.ruTrackerUsername,
                onValueChange = viewModel::setRuTrackerUsername,
                label = { Text("RuTracker gebruikersnaam") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = state.ruTrackerPassword,
                onValueChange = viewModel::setRuTrackerPassword,
                label = { Text("RuTracker wachtwoord") },
                singleLine = true,
                visualTransformation = if (showRuPass) VisualTransformation.None else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                trailingIcon = {
                    IconButton(onClick = { showRuPass = !showRuPass }) {
                        Icon(if (showRuPass) Icons.Default.VisibilityOff else Icons.Default.Visibility, null)
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            )
            Button(onClick = viewModel::saveRuTracker, modifier = Modifier.fillMaxWidth()) {
                Text("RuTracker opslaan")
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

private fun formatStorageBytes(bytes: Long): String {
    if (bytes <= 0) return "0 MB"
    val gb = bytes / 1_073_741_824.0
    val mb = bytes / 1_048_576.0
    return if (gb >= 1.0) "%.1f GB".format(gb) else "%.0f MB".format(mb)
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.primary,
    )
}
