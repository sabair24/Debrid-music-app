package com.debridmusic.app.ui.tv

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.navArgument
import com.debridmusic.app.ui.tv.catalogue.TvCatalogueScreen
import com.debridmusic.app.ui.tv.home.TvHomeScreen
import com.debridmusic.app.ui.tv.player.TvNowPlayingScreen

sealed class TvScreen(val route: String) {
    object Home : TvScreen("tv_home")
    object NowPlaying : TvScreen("tv_now_playing")
    object Catalogue : TvScreen("tv_catalogue")
    object AlbumDetail : TvScreen("tv_album/{albumId}") {
        fun createRoute(id: Long) = "tv_album/$id"
    }
}

@Composable
fun TvNavHost(navController: NavHostController) {
    NavHost(navController = navController, startDestination = TvScreen.Home.route) {

        composable(TvScreen.Home.route) {
            TvHomeScreen(
                onNowPlayingClick = { navController.navigate(TvScreen.NowPlaying.route) },
                onCatalogueClick = { navController.navigate(TvScreen.Catalogue.route) },
                onAlbumClick = { albumId ->
                    navController.navigate(TvScreen.AlbumDetail.createRoute(albumId))
                },
            )
        }

        composable(TvScreen.NowPlaying.route) {
            TvNowPlayingScreen(onBack = { navController.popBackStack() })
        }

        composable(TvScreen.Catalogue.route) {
            TvCatalogueScreen(
                onBack = { navController.popBackStack() },
                onNowPlayingClick = { navController.navigate(TvScreen.NowPlaying.route) },
            )
        }

        composable(
            route = TvScreen.AlbumDetail.route,
            arguments = listOf(navArgument("albumId") { type = NavType.LongType }),
        ) {
            // Reuses TvHomeScreen filtered by album — full album detail is a stretch goal
            TvHomeScreen(
                onNowPlayingClick = { navController.navigate(TvScreen.NowPlaying.route) },
                onCatalogueClick = { navController.navigate(TvScreen.Catalogue.route) },
                onAlbumClick = {},
            )
        }
    }
}
