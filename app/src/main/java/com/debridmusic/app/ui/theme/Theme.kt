package com.debridmusic.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val DarkColorScheme = darkColorScheme(
    primary = TealPrimary,
    onPrimary = Surface900,
    primaryContainer = TealVariant,
    onPrimaryContainer = OnSurface,
    secondary = GoldAccent,
    onSecondary = Surface900,
    secondaryContainer = Surface600,
    onSecondaryContainer = OnSurface,
    tertiary = TealVariant,
    background = Surface900,
    onBackground = OnSurface,
    surface = Surface800,
    onSurface = OnSurface,
    surfaceVariant = Surface700,
    onSurfaceVariant = OnSurfaceMuted,
    outline = Surface500,
    error = ErrorRed,
)

@Composable
fun DebridMusicTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        typography = AppTypography,
        content = content,
    )
}
