/// What the lockscreen, Control Center and the media keys see.
///
/// libmpv plays the audio; this only tells the system what is playing and hands the buttons back
/// to [PlayerStore]. It is the one thing the SwiftUI app got for free from AVFoundation, and the
/// price of having a single codebase — so it is written once, here, rather than lived without.
///
/// Only where a system asks for it: iOS, macOS and Android. On Windows the app has its own window
/// with its own buttons, and `audio_service` has nothing to talk to there.
library;

import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';
import 'paths.dart';
import 'player.dart';

bool get _wantsSystemControls => Platform.isIOS || Platform.isMacOS || Platform.isAndroid;

/// Start publishing. Safe to call anywhere: it does nothing where there is nothing to publish to,
/// and a failure to register is never a reason for the app not to start.
Future<void> initNowPlaying(NowPlayingSource player, {Uint8List? Function(Track)? cover}) async {
  if (!_wantsSystemControls) return;
  try {
    await AudioService.init(
      builder: () => NowPlayingHandler(player, cover),
      config: const AudioServiceConfig(
        // debridmusic, not debridmedia — this named a different app entirely. Harmless while
        // Android was switched off; the moment it is on, this string is the notification channel
        // the user sees in Android's own settings.
        androidNotificationChannelId: 'com.debridmusic.app.playback',
        androidNotificationChannelName: 'Afspelen',
        androidNotificationOngoing: true,
      ),
    );
  } catch (e) {
    // A missing platform implementation, or a second init during a hot restart. The app plays
    // either way; only the lockscreen goes quiet.
    debugPrint('Now Playing unavailable: $e');
  }
  await _claimTheAudio(player);
}

/// Tell the system this app is a music player, and listen for it saying otherwise.
///
/// This was missing entirely, and on a phone that is not a detail. Without a configured session
/// the app never holds audio focus: nothing pauses for a phone call or a navigation prompt, and —
/// worse — nothing NOTICES when the system takes the output away. libmpv carries on writing into a
/// sink that is no longer connected to anything, so the position advances, the buttons keep
/// working, and there is no sound. That is exactly the shape of the Android Auto complaint: a
/// track that plays on with nothing coming out, a couple of songs into a drive.
///
/// [AudioSessionConfiguration.music] is the recipe for this kind of app: media usage, music content
/// type, and a focus request that lasts until something else takes it.
Future<void> _claimTheAudio(NowPlayingSource player) async {
  if (!_wantsSystemControls) return;
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Paused BY the system, as opposed to paused by the user — only the first may resume on its
    // own. Without the distinction a call ending would restart music somebody had deliberately
    // stopped ten minutes earlier.
    var pausedByOthers = false;

    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            // Android lowers the volume itself for a navigation prompt. Pausing for it would be
            // worse than the ducking: you would lose two seconds of the song at every junction.
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            if (player.playing) {
              pausedByOthers = true;
              player.playPause();
            }
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            break;
          case AudioInterruptionType.pause:
            // The interruption is over and the focus came back: pick up where the call cut in.
            if (pausedByOthers && !player.playing) player.playPause();
            pausedByOthers = false;
          case AudioInterruptionType.unknown:
            // Focus is gone for good — another app has the audio now. Staying paused is right.
            pausedByOthers = false;
        }
      }
    });

    // Headphones out, or the earbuds walking out of range. Android requires an app to stop here;
    // without it the music jumps to the phone's speaker at whatever volume it was at.
    session.becomingNoisyEventStream.listen((_) {
      if (player.playing) player.playPause();
    });
  } catch (e) {
    debugPrint('Audio session unavailable: $e');
  }
}

/// Public only so it can be tested without a platform channel: [AudioService.init] needs one, the
/// handler itself does not.
@visibleForTesting
class NowPlayingHandler extends BaseAudioHandler with SeekHandler {
  NowPlayingHandler(this.player, this.coverFor) {
    player.addListener(_onChanged);
    _onChanged();
  }

  final NowPlayingSource player;
  final Uint8List? Function(Track)? coverFor;

  /// What was last published, so the artwork is only written to disk when something the lockscreen
  /// SHOWS has changed — this listener fires on every position tick.
  ///
  /// The path alone is not enough. Correcting the artist of the track that is playing changes no
  /// path, so this used to suppress the republish and Control Center kept the old name until the
  /// next song. The signature covers exactly the four fields [_publishItem] puts on screen.
  String? _publishedSig;
  bool _lastPlaying = false;
  bool _lastBuffering = false;
  Duration _lastPosition = Duration.zero;

  /// Joined on a NUL, which cannot occur in any of the four. A printable separator would let a
  /// title that ends where an artist begins produce the signature of a different pair.
  static String _sigOf(Track t) => [t.path, t.title, t.artist, t.album].join('\u0000');

  void _onChanged() {
    final track = player.current;
    if (track == null) {
      if (_publishedSig != null) {
        _publishedSig = null;
        mediaItem.add(null);
        playbackState.add(PlaybackState(processingState: AudioProcessingState.idle));
      }
      return;
    }

    final sig = _sigOf(track);
    if (sig != _publishedSig) {
      _publishedSig = sig;
      unawaited(_publishItem(track));
    }

    // Position moves constantly; the system only needs it when it jumps or when play/pause flips.
    // Publishing every tick makes the lockscreen scrubber stutter and wakes the OS needlessly.
    // Buffering joins the two that already break the throttle, and for the same reason: it is a
    // state the car acts on, not a number that ticks.
    final drift = (player.position - _lastPosition).inMilliseconds.abs();
    if (player.playing != _lastPlaying || player.buffering != _lastBuffering || drift > 1200) {
      _lastPlaying = player.playing;
      _lastBuffering = player.buffering;
      _lastPosition = player.position;
      _publishState();
    }
  }

  void _publishState() {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      // Said honestly rather than hardcoded to “ready”. A head unit reads this: told the app is
      // ready and playing while it is in fact waiting on the network, a car has no way to tell a
      // stall from a quiet passage, and neither does the person listening.
      processingState:
          player.buffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
      playing: player.playing,
      updatePosition: player.position,
      // Was the whole duration, unconditionally — a claim that the entire track was already in
      // hand, which over a LAN stream is never true at the start and sometimes never true at all.
      bufferedPosition: player.buffering ? player.position : player.duration,
      speed: player.playing ? 1.0 : 0.0,
      queueIndex: null,
    ));
  }

  Future<void> _publishItem(Track track) async {
    Uri? art;
    try {
      final bytes = coverFor?.call(track) ?? player.currentCover;
      if (bytes != null && bytes.length > 100) art = await _artFile(bytes);
    } catch (_) {
      // No cover is a cosmetic loss; the title still shows.
    }
    mediaItem.add(MediaItem(
      id: track.path,
      title: track.title,
      artist: track.artist,
      album: track.album.isEmpty ? null : track.album,
      duration: track.duration ?? player.duration,
      artUri: art,
    ));
    _publishState();
  }

  /// The system wants a URL for the artwork, not bytes — so the cover goes to a file named after
  /// its own contents. Same cover, same file: an album played twice writes nothing the second
  /// time, and the folder cannot grow past one file per distinct cover.
  Future<Uri?> _artFile(Uint8List bytes) async {
    final dir = appSubdir('nowplaying');
    final file = File('${dir.path}${Platform.pathSeparator}'
        '${md5.convert(bytes).toString().substring(0, 16)}.jpg');
    if (!await file.exists()) await file.writeAsBytes(bytes);
    return Uri.file(file.path);
  }

  // The store has one toggle, the system sends two distinct commands. Checking the state first is
  // not a nicety: a "play" arriving while already playing would otherwise pause the music, which
  // is exactly what happens when a headset reconnects and asks for playback.
  @override
  Future<void> play() async {
    if (!player.playing) player.playPause();
  }

  @override
  Future<void> pause() async {
    if (player.playing) player.playPause();
  }

  @override
  Future<void> skipToNext() => player.next();

  @override
  Future<void> skipToPrevious() => player.prev();

  @override
  Future<void> seek(Duration position) async => player.seek(position);

  @override
  Future<void> stop() async {
    if (player.playing) player.playPause();
    await super.stop();
  }
}
