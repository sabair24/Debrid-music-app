package com.debridmusic.app.ui.theme

import android.graphics.drawable.BitmapDrawable
import androidx.compose.animation.animateColorAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.palette.graphics.Palette
import coil.ImageLoader
import coil.request.ImageRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Extracts a dominant accent colour from an artwork URL (Roon-style dynamic
 * theming). Returns [fallback] until the image is loaded/analysed, then animates
 * to the extracted colour. Safe on null/blank URLs and load failures.
 */
@Composable
fun rememberDominantColor(url: String?, fallback: Color): State<Color> {
    val context = LocalContext.current
    var target by remember(url) { mutableStateOf(fallback) }

    LaunchedEffect(url) {
        if (url.isNullOrBlank()) { target = fallback; return@LaunchedEffect }
        runCatching {
            val loader = ImageLoader(context)
            val request = ImageRequest.Builder(context)
                .data(url)
                .allowHardware(false) // Palette needs a software bitmap
                .size(160)
                .build()
            val bitmap = (loader.execute(request).drawable as? BitmapDrawable)?.bitmap
            if (bitmap != null) {
                val palette = withContext(Dispatchers.Default) { Palette.from(bitmap).generate() }
                val swatch = palette.darkVibrantSwatch
                    ?: palette.vibrantSwatch
                    ?: palette.darkMutedSwatch
                    ?: palette.dominantSwatch
                swatch?.let { target = Color(it.rgb) }
            }
        }
    }

    return animateColorAsState(targetValue = target, label = "dominantColor")
}
