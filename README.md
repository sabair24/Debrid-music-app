# Debrid Music

A Tidal-like FLAC music app for **Android** and **Android TV**, built with Kotlin + Jetpack Compose.

## Phases

| Phase | Status | Description |
|-------|--------|-------------|
| 1 | ✅ Done | Project scaffold · Local library (Room) · Media3/ExoPlayer player |
| 2 | Planned | Catalogue metadata via MusicBrainz / Cover Art Archive / Last.fm / Discogs |
| 3 | Planned | TorBox debrid API — search, stream, download |
| 4 | Planned | Android TV UI (androidx.tv, leanback-style navigation) |
| 5 | Planned | Playlists · EQ · cross-fade · scrobbling · offline cache |

## Tech stack

- **Language**: Kotlin
- **UI**: Jetpack Compose · Material 3 · `androidx.tv` for TV
- **Playback**: Media3 / ExoPlayer (native FLAC support)
- **DI**: Hilt
- **DB**: Room
- **Networking**: Retrofit + OkHttp
- **Images**: Coil
- **Async**: Kotlin Coroutines + Flow

## Phase 1 features

- Scan device storage for music files (FLAC, MP3, AAC, OGG, …)
- Room database — Track / Album / Artist entities
- Library screen with Tracks / Albums / Artists tabs
- Full-screen Now Playing screen with seek bar and transport controls
- Persistent Mini Player at the bottom of every screen
- FLAC badge on lossless tracks
- Search across tracks, albums and artists
- Dark Tidal-inspired theme (teal primary, gold accent)

## Building

```bash
./gradlew assembleDebug
```

Requires Android SDK 35 and JDK 17.
