package com.debridmusic.app.ui.tv

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController

@Composable
fun TvApp() {
    val navController = rememberNavController()
    val backStack by navController.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route

    var drawerFocused by remember { mutableStateOf(false) }
    val drawerWidth by animateDpAsState(
        targetValue = if (drawerFocused) 200.dp else 64.dp,
        animationSpec = tween(durationMillis = 200),
        label = "drawer_width",
    )

    Row(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {

        // ── Side navigation drawer ──────────────────────────────────────────
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween,
            modifier = Modifier
                .width(drawerWidth)
                .fillMaxHeight()
                .background(MaterialTheme.colorScheme.surface)
                .onFocusChanged { drawerFocused = it.hasFocus }
                .selectableGroup()
                .padding(vertical = 24.dp),
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // App logo mark
                Icon(
                    imageVector = Icons.Default.MusicNote,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier
                        .size(32.dp)
                        .padding(bottom = 16.dp),
                )
                TvNavItem(
                    icon = Icons.Default.Home,
                    label = "Home",
                    selected = currentRoute == TvScreen.Home.route,
                    expanded = drawerFocused,
                    onClick = {
                        navController.navigate(TvScreen.Home.route) {
                            popUpTo(TvScreen.Home.route) { inclusive = true }
                        }
                    },
                )
                TvNavItem(
                    icon = Icons.Default.CloudDownload,
                    label = "Ontdekken",
                    selected = currentRoute == TvScreen.Catalogue.route,
                    expanded = drawerFocused,
                    onClick = { navController.navigate(TvScreen.Catalogue.route) },
                )
            }

            TvNavItem(
                icon = Icons.Default.Settings,
                label = "Instellingen",
                selected = false,
                expanded = drawerFocused,
                onClick = { /* Settings are handled on the phone; TV shows read-only */ },
            )
        }

        // ── Main content ────────────────────────────────────────────────────
        Box(modifier = Modifier.weight(1f).fillMaxHeight()) {
            TvNavHost(navController)
        }
    }
}

@Composable
private fun TvNavItem(
    icon: ImageVector,
    label: String,
    selected: Boolean,
    expanded: Boolean,
    onClick: () -> Unit,
) {
    val focusRequester = remember { FocusRequester() }
    var isFocused by remember { mutableStateOf(false) }

    Surface(
        onClick = onClick,
        color = when {
            selected -> MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
            isFocused -> MaterialTheme.colorScheme.surfaceVariant
            else -> MaterialTheme.colorScheme.surface
        },
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp)
            .focusRequester(focusRequester)
            .onFocusChanged { isFocused = it.isFocused }
            .focusable(),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 14.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                tint = if (selected || isFocused) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(24.dp),
            )
            if (expanded) {
                Spacer(Modifier.width(12.dp))
                Text(
                    text = label,
                    style = MaterialTheme.typography.titleMedium,
                    color = if (selected || isFocused) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.onSurface,
                )
            }
        }
    }
}
