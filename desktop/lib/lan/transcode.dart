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

  /// Convert [file] to a FILE at [maxSampleRate], and hand back where it landed.
  ///
  /// A file, not a pipe, and that is the whole point. Measured against the Sonos Amp in the living
  /// room on 2026-08-08: piped through `resample` the speaker accepts the URL, reports PLAYING, and
  /// its reported track length keeps creeping up (0:21, 0:26, ...) while the position never leaves
  /// 0:00:00. It never renders a note. The same speaker plays an ordinary 44.1 kHz file from the
  /// same server perfectly, position advancing 0:04, 0:09, 0:14 — so it is not the network, the
  /// token, the address or the metadata.
  ///
  /// The difference is the shape of the response. A pipe has no Content-Length, so the server sends
  /// it chunked, and FLAC coming out of a pipe carries an unknown sample count in its header. Sonos
  /// reads that as an endless radio stream. Written to disk first, the file has a length, a real
  /// header, and Range support — and it plays.
  ///
  /// The cost is honest: the first play of a hi-res track waits for the conversion, which at
  /// compression level 0 is a second or two. The second play is instant, because the result is
  /// kept. Cheaper than a track that never plays.
  Future<File?> resampleToFile(File file, {required int maxSampleRate, required Directory cacheDir}) async {
    final ffmpeg = path;
    if (ffmpeg == null) return null;
    final naam = '${_sleutel(file, maxSampleRate)}.flac';
    final uit = File('${cacheDir.path}${Platform.pathSeparator}$naam');
    // Already converted, and not a leftover from a crash halfway through.
    if (uit.existsSync() && uit.lengthSync() > 1024) return uit;
    try {
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
      final tijdelijk = File('${uit.path}.tmp');
      final result = await Process.run(ffmpeg, [
        '-hide_banner', '-loglevel', 'error',
        '-y',
        '-i', file.path,
        // Same filter and the same reasoning as the piped version: plain aresample, because plenty
        // of ffmpeg builds ship without soxr and asking for it fails the whole graph silently.
        '-af', 'aresample=$maxSampleRate:filter_size=256',
        '-sample_fmt', 's32',
        '-c:a', 'flac',
        '-compression_level', '0',
        tijdelijk.path,
      ]);
      if (result.exitCode != 0 || !tijdelijk.existsSync()) {
        debugPrint('ffmpeg kon niet omzetten: ${result.stderr}');
        if (tijdelijk.existsSync()) tijdelijk.deleteSync();
        return null;
      }
      // Rename last, so a half-written file is never mistaken for a finished one.
      tijdelijk.renameSync(uit.path);
      _snoei(cacheDir);
      return uit;
    } catch (e) {
      debugPrint('omzetten mislukt: $e');
      return null;
    }
  }

  /// Same source and same ceiling means the same result, so it is looked up rather than made again.
  static String _sleutel(File file, int rate) {
    final st = file.statSync();
    return '${file.path.hashCode.toUnsigned(32).toRadixString(16)}'
        '_${st.size}_$rate';
  }

  /// Keep the newest [_bewaar] conversions and drop the rest.
  ///
  /// A converted 24/48 track is tens of megabytes and these are throwaway copies; without a ceiling
  /// a long evening of casting quietly fills the disk the music lives on.
  static const _bewaar = 24;

  static void _snoei(Directory dir) {
    try {
      final bestanden = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.flac')).toList();
      if (bestanden.length <= _bewaar) return;
      bestanden.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final f in bestanden.skip(_bewaar)) {
        try {
          f.deleteSync();
        } catch (_) {/* in gebruik; volgende keer weer */}
      }
    } catch (_) {/* opruimen mag nooit het afspelen breken */}
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
