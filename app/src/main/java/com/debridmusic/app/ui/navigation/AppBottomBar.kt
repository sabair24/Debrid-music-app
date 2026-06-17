package com.debridmusic.app.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector

data class BottomDest(val route: String, val label: String, val icon: ImageVector)

val BOTTOM_DESTS = listOf(
    BottomDest(Screen.Home.route, "Home", Icons.Default.Home),
    BottomDest(Screen.Library.route, "Bibliotheek", Icons.Default.LibraryMusic),
    BottomDest(Screen.CatalogueSearch.route, "Zoeken", Icons.Default.Search),
    BottomDest(Screen.Settings.route, "Instellingen", Icons.Default.Settings),
)

@Composable
fun AppBottomBar(currentRoute: String?, onSelect: (String) -> Unit) {
    NavigationBar {
        BOTTOM_DESTS.forEach { dest ->
            NavigationBarItem(
                selected = currentRoute == dest.route,
                onClick = { onSelect(dest.route) },
                icon = { Icon(dest.icon, contentDescription = dest.label) },
                label = { Text(dest.label) },
            )
        }
    }
}
