package com.debridmusic.app.ui.navigation

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.navArgument
import com.debridmusic.app.ui.album.AlbumDetailScreen
import com.debridmusic.app.ui.artist.ArtistDetailScreen
import com.debridmusic.app.ui.browse.AlbumBrowseScreen
import com.debridmusic.app.ui.browse.ArtistBrowseScreen
import com.debridmusic.app.ui.catalogue.CatalogueSearchScreen
import com.debridmusic.app.ui.downloads.DownloadsScreen
import com.debridmusic.app.ui.home.HomeScreen
import com.debridmusic.app.ui.library.LibraryScreen
import com.debridmusic.app.ui.player.PlayerScreen
import com.debridmusic.app.ui.playlist.PlaylistDetailScreen
import com.debridmusic.app.ui.settings.SettingsScreen
import com.debridmusic.app.ui.soulseek.SoulseekSearchScreen

sealed class Screen(val route: String) {
    object Home : Screen("home")
    object Library : Screen("library")
    object NowPlaying : Screen("now_playing")
    object Settings : Screen("settings")
    object CatalogueSearch : Screen("catalogue_search")
    object Downloads : Screen("downloads")
    object SoulseekSearch : Screen("soulseek_search")
    object AlbumDetail : Screen("album/{albumId}") {
        fun createRoute(albumId: Long) = "album/$albumId"
    }
    object ArtistDetail : Screen("artist/{artistId}") {
        fun createRoute(artistId: Long) = "artist/$artistId"
    }
    object PlaylistDetail : Screen("playlist/{playlistId}") {
        fun createRoute(playlistId: Long) = "playlist/$playlistId"
    }
    // Online "Stremio-style" browse (Deezer ids), distinct from local detail screens.
    object ArtistBrowse : Screen("artist_browse/{deezerArtistId}") {
        fun createRoute(deezerArtistId: Long) = "artist_browse/$deezerArtistId"
    }
    object AlbumBrowse : Screen("album_browse/{deezerAlbumId}") {
        fun createRoute(deezerAlbumId: Long) = "album_browse/$deezerAlbumId"
    }
}

private val TOP_LEVEL_ROUTES = BOTTOM_DESTS.map { it.route }.toSet()

@Composable
fun AppNavHost(navController: NavHostController) {
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route
    val showBottomBar = currentRoute in TOP_LEVEL_ROUTES

    fun switchTab(route: String) {
        if (route == currentRoute) return
        navController.navigate(route) {
            popUpTo(Screen.Home.route) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }

    Scaffold(
        // No top inset from this outer scaffold — inner screens handle their own.
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            if (showBottomBar) AppBottomBar(currentRoute = currentRoute, onSelect = ::switchTab)
        },
    ) { scaffoldPadding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Home.route,
            modifier = Modifier.padding(scaffoldPadding),
        ) {
            composable(Screen.Home.route) {
                HomeScreen(
                    onAlbumClick = { navController.navigate(Screen.AlbumDetail.createRoute(it)) },
                    onArtistClick = { navController.navigate(Screen.ArtistDetail.createRoute(it)) },
                    onNowPlayingClick = { navController.navigate(Screen.NowPlaying.route) },
                    onStreamOnlineClick = { switchTab(Screen.CatalogueSearch.route) },
                )
            }

            composable(Screen.Library.route) {
            LibraryScreen(
                onTrackClick = { navController.navigate(Screen.NowPlaying.route) },
                onAlbumClick = { albumId ->
                    navController.navigate(Screen.AlbumDetail.createRoute(albumId))
                },
                onArtistClick = { artistId ->
                    navController.navigate(Screen.ArtistDetail.createRoute(artistId))
                },
                onSettingsClick = { switchTab(Screen.Settings.route) },
                onStreamOnlineClick = { switchTab(Screen.CatalogueSearch.route) },
                onSoulseekClick = { navController.navigate(Screen.SoulseekSearch.route) },
                onDownloadsClick = { navController.navigate(Screen.Downloads.route) },
                onPlaylistClick = { playlistId ->
                    navController.navigate(Screen.PlaylistDetail.createRoute(playlistId))
                },
            )
        }

        composable(Screen.CatalogueSearch.route) {
            CatalogueSearchScreen(
                onBack = { navController.popBackStack() },
                onNowPlayingClick = { navController.navigate(Screen.NowPlaying.route) },
                onArtistClick = { deezerArtistId ->
                    navController.navigate(Screen.ArtistBrowse.createRoute(deezerArtistId))
                },
            )
        }

        composable(Screen.NowPlaying.route) {
            PlayerScreen(onBack = { navController.popBackStack() })
        }

        composable(Screen.Settings.route) {
            SettingsScreen(onBack = { navController.popBackStack() })
        }

        composable(Screen.SoulseekSearch.route) {
            SoulseekSearchScreen(
                onBack = { navController.popBackStack() },
                onNowPlayingClick = { navController.navigate(Screen.NowPlaying.route) },
            )
        }

        composable(Screen.Downloads.route) {
            DownloadsScreen(
                onBack = { navController.popBackStack() },
                onNowPlayingClick = { navController.navigate(Screen.NowPlaying.route) },
            )
        }

        composable(
            route = Screen.AlbumDetail.route,
            arguments = listOf(navArgument("albumId") { type = NavType.LongType }),
        ) {
            AlbumDetailScreen(
                onBack = { navController.popBackStack() },
                onNowPlayingClick = { navController.navigate(Screen.NowPlaying.route) },
            )
        }

        composable(
            route = Screen.ArtistDetail.route,
            arguments = listOf(navArgument("artistId") { type = NavType.LongType }),
        ) {
            ArtistDetailScreen(
                onBack = { navController.popBackStack() },
                onAlbumClick = { albumId ->
                    navController.navigate(Screen.AlbumDetail.createRoute(albumId))
                },
                onNowPlayingClick = { navController.navigate(Screen.NowPlaying.route) },
            )
        }

        composable(
            route = Screen.PlaylistDetail.route,
            arguments = listOf(navArgument("playlistId") { type = NavType.LongType }),
        ) {
            PlaylistDetailScreen(
                onBack = { navController.popBackStack() },
                onNowPlayingClick = { navController.navigate(Screen.NowPlaying.route) },
            )
        }

        composable(
            route = Screen.ArtistBrowse.route,
            arguments = listOf(navArgument("deezerArtistId") { type = NavType.LongType }),
        ) {
            ArtistBrowseScreen(
                onBack = { navController.popBackStack() },
                onAlbumClick = { deezerAlbumId ->
                    navController.navigate(Screen.AlbumBrowse.createRoute(deezerAlbumId))
                },
                onNowPlayingClick = { navController.navigate(Screen.NowPlaying.route) },
            )
        }

        composable(
            route = Screen.AlbumBrowse.route,
            arguments = listOf(navArgument("deezerAlbumId") { type = NavType.LongType }),
        ) {
            AlbumBrowseScreen(
                onBack = { navController.popBackStack() },
                onNowPlayingClick = { navController.navigate(Screen.NowPlaying.route) },
            )
        }
        }
    }
}
