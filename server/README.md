# DebridMusic Server

A lightweight, self-hosted music server. It indexes one or more folders on your PC and
streams to the DebridMusic apps (Android phone, Shield TV, and the upcoming iPad/Mac apps)
over your LAN. Single Kotlin/Ktor fat-JAR — runs anywhere with Java 17+.

It also ships a **built-in web app** (browse + play your library in any browser) and can
**cast to Sonos / DLNA renderers** on the network.

## Windows desktop app

The easiest way to run it on a PC is the packaged desktop app — a self-contained
`DebridMusic.exe` (bundles its own JRE, no Java install needed):

```powershell
# build it (needs a JDK 17+ on JAVA_HOME; uses its jpackage)
powershell -ExecutionPolicy Bypass -File server\package-windows.ps1
# -> server\dist\DebridMusic\DebridMusic.exe
```

Double-click `DebridMusic.exe`. It:
- indexes your music folder (defaults to `D:\Flac music 2024`; a folder picker appears the
  first time if that path doesn't exist — change it later from the tray menu),
- lives in the **system tray** (Open app · Copy access token · Copy LAN link · Change folder),
- opens the web app in your browser at `http://localhost:4533/?token=…`,
- keeps its index + token in `%LOCALAPPDATA%\DebridMusic`.

Open the same **LAN link** (`http://<pc-ip>:4533/?token=…`, shown in the tray) on your
iPad, phone or Shield TV browser to use the app there too.

### Casting to Sonos / DLNA
The web app's speaker picker (bottom-right of the player bar) lists renderers found on the
LAN via SSDP — Sonos, DLNA receivers, etc. Pick one and playback happens on that device;
the stream URL handed to the speaker uses the PC's LAN IP on the *same subnet* as the
speaker. (Chromecast/Shield-cast is not UPnP — use the native Android TV client for that,
or a UPnP-renderer app on the Shield.)

## Run

```bash
# build (CI does this automatically; locally you need Gradle 8.7+)
gradle shadowJar

# run — point MUSIC_ROOTS at your music folder(s)
MUSIC_ROOTS=/path/to/Music java -jar build/libs/musicserver.jar
```

Or with a config file (`config.properties`, same keys as the env vars):

```properties
MUSIC_ROOTS=/srv/music,/mnt/usb/flac
PORT=4533
AUTH_TOKEN=my-secret
```
```bash
java -jar build/libs/musicserver.jar config.properties
```

On first start an auth token is generated and printed (and saved to `data/token.txt`).
Paste that token into the app: **Settings → Music Server**.

## Configuration

| Var | Default | Purpose |
|-----|---------|---------|
| `MUSIC_ROOTS` | — (required) | Folder(s) to index, comma- or path-separator-separated |
| `PORT` | `4533` | HTTP port |
| `BIND` | `0.0.0.0` | Bind address |
| `AUTH_TOKEN` | auto-generated | Bearer token clients must send |
| `DATA_DIR` | `./data` | SQLite index + token live here |
| `USERNAME` / `PASSWORD` | `music` / token | Optional, for `POST /auth/token` |

## API

| Method | Path | Auth |
|--------|------|------|
| GET | `/health` | none |
| POST | `/auth/token` | none |
| GET | `/api/library/artists` · `/albums` · `/tracks` | bearer |
| GET | `/api/catalog` | bearer |
| GET | `/api/search?q=` | bearer |
| POST | `/api/ingest` (multipart `file` + `metadata`) | bearer |
| GET | `/stream/{trackId}` (HTTP Range) | bearer |
| GET | `/art/{albumId}` | bearer |

Auth is `Authorization: Bearer <token>` (or `?token=` for players that can't set headers).

## Quick test

```bash
curl http://localhost:4533/health
curl -H "Authorization: Bearer <token>" http://localhost:4533/api/library/tracks
curl -r 0-1023 -H "Authorization: Bearer <token>" http://localhost:4533/stream/<id> -D -   # expect 206
```

New files dropped into the music folder (including pushes from the app's downloader) are
picked up automatically by the file watcher.
