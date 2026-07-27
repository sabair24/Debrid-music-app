# Debrid Music

Your own FLAC library, the same on every screen: Windows, macOS, iPad, an Android phone and the
Android TV in the living room. One Flutter codebase — not five apps kept in step by hand.

## How it is put together

One machine owns the music. It scans the folder, holds the corrections and the artwork you chose,
and serves the rest over the local network:

```
   PC / Mac  ──── the music lives here, scans it, serves it
      │
      ├── iPad, phone, Android TV   ── library over LAN, streams the audio
      └── Sonos · KEF · the TV       ── the PC sends the audio straight to the speaker
```

Everything a device shows comes from that one library, so a cover you fix or a pressing you pin
appears everywhere at once. Sign in with a Firebase account and the devices find the PC by
themselves; without an account there is a six-digit pairing code.

The PC also does the looking-up. What a record IS — which pressing, the label's tracklist, what is
missing from yours — is worked out once, stored next to the music, and handed to every device that
asks. A phone never queries MusicBrainz itself.

## The code

Everything is in **`desktop/`**. One Flutter project, every platform:

| | |
|---|---|
| `lib/` | the app — one UI, sized for a window, a tablet, a phone and a ten-foot screen |
| `lib/lan/` | the server the PC runs, and the client the other devices use |
| `lib/cloud/` | Firebase auth and Firestore, over REST — no SDK |
| `desktop/android`, `ios`, `macos`, `windows` | the platform shells |
| `server/` | a small helper service, built separately |

Playback is libmpv through `media_kit`, so a FLAC plays bit-perfect on every platform including
Android TV over HDMI.

## Building

```bash
cd desktop
flutter test          # the suite; anything under *_live_test.dart calls real APIs
flutter build apk     # phone and Android TV
flutter build macos   # and windows / ios likewise
```

Releases are cut by tagging. **One tag ships all four platforms** — `win-v1.2.3` builds the Windows
installer, the Mac app, the iPad build for TestFlight and the APK. They used to be tagged
separately, which is how the Mac once ended up three versions behind the PC.

## History

This started as a Kotlin + Jetpack Compose app for Android and Android TV. It was replaced by the
Flutter app, and the Kotlin source was removed once the television ran the new build — 17,000 lines
that existed only so the TV could look like the rest. Git still has it if it is ever wanted.
