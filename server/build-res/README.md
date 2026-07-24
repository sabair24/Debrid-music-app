# build-res

`icon.ico` is the Windows app icon consumed by `../package-windows.ps1` (jpackage `--icon`).
It is committed artwork, **not** a build output — do not regenerate it from this repo.

The mark (teal concentric "D" + play triangle) is maintained in the separate
`debrid-music-icon` design project, whose source of truth is
`svg/debrid-music-mark.svg`. To change the icon, edit it there, re-export the
platform bundles, then copy across:

| Copy from (design project) | To (here) |
|---|---|
| `windows/app_icon.ico` | `server/build-res/icon.ico` |
| `png/` 256 render of the light icon | `server/src/main/resources/webui/logo.png` |

`webui/logo.png` is the web UI favicon (`webui/index.html`) and tray image, so it
needs updating alongside the `.ico` or the two drift apart.

A `IconGen.java` used to draw an older purple/teal music-notes icon procedurally and
write both files. It was deleted once the icon moved to the vector pipeline above —
running it would have silently reverted the artwork.
