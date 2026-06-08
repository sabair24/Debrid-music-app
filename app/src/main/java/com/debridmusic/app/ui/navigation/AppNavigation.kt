package com.debridmusic.app.ui.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.navArgument
import com.debridmusic.app.ui.album.AlbumDetailScreen
import com.debridmusic.app.ui.artist.ArtistDetailScreen
import com.debridmusic.app.ui.library.LibraryScreen
import com.debridmusic.app.ui.player.PlayerScreen
import com.debridmusic.app.ui.settings.SettingsScreen

sealed class Screen(val route: String) {
    object Library : Screen("library")
    object NowPlaying : Screen("now_playing")
    object Settings : Screen("settings")
    object AlbumDetail : Screen("album/{albumId}") {
        fun createRoute(albumId: Long) = "album/$albumId"
    }
    object ArtistDetail : Screen("artist/{artistId}") {
        fun createRoute(artistId: Long) = "artist/$artistId"
    }
}

@Composable
fun AppNavHost(navController: NavHostController) {
    NavHost(
        navController = navController,
        startDestination = Screen.Library.route,
    ) {
        composable(Screen.Library.route) {
            LibraryScreen(
                onTrackClick = { navController.navigate(Screen.NowPlaying.route) },
                onAlbumClick = { albumId ->
                    navController.navigate(Screen.AlbumDetail.createRoute(albumId))
                },
                onArtistClick = { artistId ->
                    navController.navigate(Screen.ArtistDetail.createRoute(artistId))
                },
                onSettingsClick = { navController.navigate(Screen.Settings.route) },
            )
        }

        composable(Screen.NowPlaying.route) {
            PlayerScreen(onBack = { navController.popBackStack() })
        }

        composable(Screen.Settings.route) {
            SettingsScreen(onBack = { navController.popBackStack() })
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
    }
}
