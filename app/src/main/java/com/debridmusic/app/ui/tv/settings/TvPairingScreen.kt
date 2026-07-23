package com.debridmusic.app.ui.tv.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.debridmusic.app.server.DiscoveredServer

/**
 * Pair this TV with the PC, using only the D-pad.
 *
 * The keypad is on screen rather than relying on Android TV's on-screen keyboard: six large
 * targets in a grid are three or four remote presses per digit, where the system keyboard is a
 * hunt across a QWERTY layout for each one.
 */
@Composable
fun TvPairingScreen(
    onBack: () -> Unit,
    viewModel: TvPairingViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val firstKey = remember { FocusRequester() }

    LaunchedEffect(state.selected) {
        if (state.selected != null) runCatching { firstKey.requestFocus() }
    }

    Row(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 48.dp, vertical = 32.dp),
        horizontalArrangement = Arrangement.spacedBy(48.dp),
    ) {
        // ── Which PC ────────────────────────────────────────────────────────
        Column(modifier = Modifier.weight(1f)) {
            Text("Koppel met je pc", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(6.dp))
            Text(
                "Open DebridMusic op je pc → Instellingen → Apparaat koppelen. " +
                    "Typ de zes cijfers hiernaast in.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(20.dp))

            if (state.connectedUrl.isNotBlank()) {
                Text(
                    "Nu verbonden met ${state.connectedUrl}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.height(12.dp))
            }

            when {
                state.searching -> Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(10.dp))
                    Text("Zoeken op je netwerk…", style = MaterialTheme.typography.bodyMedium)
                }

                state.servers.isEmpty() -> Column {
                    Text(
                        state.message.ifBlank { "Geen pc gevonden." },
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Spacer(Modifier.height(12.dp))
                    Button(onClick = viewModel::search) { Text("Opnieuw zoeken") }
                }

                else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(state.servers) { server ->
                        ServerRow(
                            server = server,
                            selected = server == state.selected,
                            onClick = { viewModel.select(server) },
                        )
                    }
                }
            }

            Spacer(Modifier.weight(1f))
            TextButton(onClick = onBack) { Text("Terug") }
        }

        // ── The six digits ──────────────────────────────────────────────────
        Column(
            modifier = Modifier.weight(1f),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                repeat(6) { i ->
                    val digit = state.code.getOrNull(i)?.toString() ?: ""
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .size(width = 44.dp, height = 58.dp)
                            .border(
                                width = 2.dp,
                                color = if (digit.isEmpty()) MaterialTheme.colorScheme.outline
                                else MaterialTheme.colorScheme.primary,
                                shape = RoundedCornerShape(8.dp),
                            ),
                    ) {
                        Text(digit, fontSize = 26.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }

            Spacer(Modifier.height(20.dp))

            // 1-9, then 0 and delete — three columns, so left/right/up/down all land somewhere.
            val keys = listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "OK")
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                keys.chunked(3).forEachIndexed { row, group ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        group.forEachIndexed { col, key ->
                            Keypad(
                                label = key,
                                enabled = when (key) {
                                    "OK" -> state.code.length == 6 && !state.pairing
                                    else -> !state.pairing
                                },
                                modifier = if (row == 0 && col == 0) Modifier.focusRequester(firstKey)
                                else Modifier,
                                onClick = {
                                    when (key) {
                                        "⌫" -> viewModel.deleteDigit()
                                        "OK" -> viewModel.pair()
                                        else -> viewModel.appendDigit(key)
                                    }
                                },
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(18.dp))
            if (state.message.isNotBlank()) {
                Text(
                    state.message,
                    textAlign = TextAlign.Center,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (state.trackCount > 0) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun ServerRow(server: DiscoveredServer, selected: Boolean, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(10.dp),
        color = when {
            selected -> MaterialTheme.colorScheme.primary.copy(alpha = 0.20f)
            focused -> MaterialTheme.colorScheme.surfaceVariant
            else -> MaterialTheme.colorScheme.surface
        },
        modifier = Modifier
            .fillMaxWidth()
            .onFocusChanged { focused = it.isFocused }
            .focusable(),
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Text(server.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(
                server.baseUrl,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun Keypad(
    label: String,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    var focused by remember { mutableStateOf(false) }
    Surface(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(10.dp),
        color = when {
            !enabled -> MaterialTheme.colorScheme.surface.copy(alpha = 0.4f)
            focused -> MaterialTheme.colorScheme.primary
            else -> MaterialTheme.colorScheme.surfaceVariant
        },
        modifier = modifier
            .size(width = 74.dp, height = 56.dp)
            .onFocusChanged { focused = it.isFocused },
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                label,
                fontSize = if (label.length > 1) 16.sp else 22.sp,
                fontWeight = FontWeight.SemiBold,
                color = when {
                    !enabled -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                    focused -> Color.Black
                    else -> MaterialTheme.colorScheme.onSurface
                },
            )
        }
    }
}
