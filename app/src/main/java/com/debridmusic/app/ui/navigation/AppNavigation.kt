package com.debridmusic.app.ui.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.navArgument
import com.debridmusic.app.ui.library.LibraryScreen
import com.debridmusic.app.ui.player.PlayerScreen

sealed class Screen(val route: String) {
    object Library : Screen("library")
    object NowPlaying : Screen("now_playing")
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
            )
        }

        composable(Screen.NowPlaying.route) {
            PlayerScreen(onBack = { navController.popBackStack() })
        }

        composable(
            route = Screen.AlbumDetail.route,
            arguments = listOf(navArgument("albumId") { type = NavType.LongType }),
        ) { backStack ->
            val albumId = backStack.arguments?.getLong("albumId") ?: return@composable
            LibraryScreen(
                filterAlbumId = albumId,
                onTrackClick = { navController.navigate(Screen.NowPlaying.route) },
                onAlbumClick = {},
                onArtistClick = { artistId ->
                    navController.navigate(Screen.ArtistDetail.createRoute(artistId))
                },
                onBack = { navController.popBackStack() },
            )
        }

        composable(
            route = Screen.ArtistDetail.route,
            arguments = listOf(navArgument("artistId") { type = NavType.LongType }),
        ) { backStack ->
            val artistId = backStack.arguments?.getLong("artistId") ?: return@composable
            LibraryScreen(
                filterArtistId = artistId,
                onTrackClick = { navController.navigate(Screen.NowPlaying.route) },
                onAlbumClick = { albumId ->
                    navController.navigate(Screen.AlbumDetail.createRoute(albumId))
                },
                onArtistClick = {},
                onBack = { navController.popBackStack() },
            )
        }
    }
}
