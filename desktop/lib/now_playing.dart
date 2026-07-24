/// What the lockscreen, Control Center and the media keys see.
///
/// libmpv plays the audio; this only tells the system what is playing and hands the buttons back
/// to [PlayerStore]. It is the one thing the SwiftUI app got for free from AVFoundation, and the
/// price of having a single codebase — so it is written once, here, rather than lived without.
///
/// Only where a system asks for it: iOS and macOS. On Windows the app has its own window with its
/// own buttons, and `audio_service` has nothing to talk to there.
library;

import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';
import 'paths.dart';
import 'player.dart';

bool get _wantsSystemControls => Platform.isIOS || Platform.isMacOS;

/// Start publishing. Safe to call anywhere: it does nothing where there is nothing to publish to,
/// and a failure to register is never a reason for the app not to start.
Future<void> initNowPlaying(NowPlayingSource player, {Uint8List? Function(Track)? cover}) async {
  if (!_wantsSystemControls) return;
  try {
    await AudioService.init(
      builder: () => NowPlayingHandler(player, cover),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.debridmedia.music.playback',
        androidNotificationChannelName: 'Afspelen',
        androidNotificationOngoing: true,
      ),
    );
  } catch (e) {
    // A missing platform implementation, or a second init during a hot restart. The app plays
    // either way; only the lockscreen goes quiet.
    debugPrint('Now Playing unavailable: $e');
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

  /// The last track published, so the artwork is only written to disk when the track really
  /// changes — this listener fires on every position tick.
  String? _publishedPath;
  bool _lastPlaying = false;
  Duration _lastPosition = Duration.zero;

  void _onChanged() {
    final track = player.current;
    if (track == null) {
      if (_publishedPath != null) {
        _publishedPath = null;
        mediaItem.add(null);
        playbackState.add(PlaybackState(processingState: AudioProcessingState.idle));
      }
      return;
    }

    if (track.path != _publishedPath) {
      _publishedPath = track.path;
      unawaited(_publishItem(track));
    }

    // Position moves constantly; the system only needs it when it jumps or when play/pause flips.
    // Publishing every tick makes the lockscreen scrubber stutter and wakes the OS needlessly.
    final drift = (player.position - _lastPosition).inMilliseconds.abs();
    if (player.playing != _lastPlaying || drift > 1200) {
      _lastPlaying = player.playing;
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
      processingState: AudioProcessingState.ready,
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.duration,
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
