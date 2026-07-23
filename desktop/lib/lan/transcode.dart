import 'dart:io';

import 'package:flutter/foundation.dart';

/// Converts a track on the fly when a speaker cannot take the original.
///
/// This exists for one reason: **Sonos plays FLAC to 24 bit but only to 48 kHz, and skips a file
/// above that instead of downsampling it.** No error is raised anywhere — the track simply does
/// not play, and a hi-res album goes quiet song by song. Converting to 24/48 keeps the best
/// quality Sonos will actually accept.
///
/// Only ever used for a speaker with a stated ceiling. The Shield, the KEF and this app all get
/// the untouched file.
class Transcoder {
  Transcoder({String? ffmpegPath}) : _explicitPath = ffmpegPath;

  final String? _explicitPath;
  String? _resolved;
  bool _looked = false;

  /// Where ffmpeg is, or null when it isn't installed.
  String? get path {
    if (_looked) return _resolved;
    _looked = true;
    _resolved = _explicitPath ?? _find();
    return _resolved;
  }

  bool get available => path != null;

  static String? _find() {
    final candidates = Platform.isWindows
        ? const [
            r'ffmpeg.exe',
            r'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
            r'C:\ffmpeg\bin\ffmpeg.exe',
          ]
        : const ['/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg', '/usr/bin/ffmpeg', 'ffmpeg'];
    for (final candidate in candidates) {
      try {
        final result = Process.runSync(candidate, ['-version']);
        if (result.exitCode == 0) return candidate;
      } catch (_) {/* not there — try the next */}
    }
    return null;
  }

  /// Stream [file] resampled to at most [maxSampleRate], as FLAC.
  ///
  /// Piped rather than written to a temp file: a speaker starts playing as the bytes arrive, and
  /// converting a 200 MB hi-res track to disk first would mean a long silence before anything
  /// happens — and a folder that fills up.
  ///
  /// The trade-off is honest: the result is no longer bit-identical to the file on disk. It is
  /// the best Sonos will take, and the alternative is silence.
  Future<Process?> resample(File file, {required int maxSampleRate}) async {
    final ffmpeg = path;
    if (ffmpeg == null) return null;
    try {
      return await Process.start(ffmpeg, [
        '-hide_banner', '-loglevel', 'error',
        '-i', file.path,
        // Plain aresample — NOT `resampler=soxr`. Plenty of ffmpeg builds, including Homebrew's
        // on this machine, ship without soxr, and asking for it fails the whole filter graph:
        // ffmpeg exits with "Requested resampling engine is unavailable" and writes nothing, so
        // the speaker gets an empty stream. swr's own resampler is built in everywhere and is
        // more than good enough — a 96→48 conversion is an exact 2:1 ratio.
        '-af', 'aresample=$maxSampleRate:filter_size=256',
        '-sample_fmt', 's32',
        '-c:a', 'flac',
        '-compression_level', '0', // speed over size: this is thrown away after playing
        '-f', 'flac',
        'pipe:1',
      ]);
    } catch (e) {
      debugPrint('could not start ffmpeg: $e');
      return null;
    }
  }
}
