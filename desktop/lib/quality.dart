// Audio-quality detection for search results, so the user can see (and filter by)
// what they're actually getting. Torrents only expose a name → parsed heuristically;
// Soulseek files expose real bitrate/duration.

enum QTier { hires, lossless, lossy, unknown }

class Quality {
  final String label; // e.g. "FLAC 24/96", "FLAC · 1006k", "MP3 320", "DSD", "?"
  final QTier tier;
  const Quality(this.label, this.tier);
  bool get lossless => tier == QTier.hires || tier == QTier.lossless;
}

final _dsd = RegExp(r'\b(dsd\d*|sacd|dsf|dff|2\.8\s?mhz|5\.6\s?mhz)\b', caseSensitive: false);
final _flac = RegExp(r'\bflac\b', caseSensitive: false);
final _losslessOther = RegExp(r'\b(alac|ape|wav|wavpack|tak|tta|aiff|lossless)\b', caseSensitive: false);
final _lossy = RegExp(r'\b(mp3|aac|m4a|ogg|opus|vorbis|lossy|cbr|vbr)\b', caseSensitive: false);
// depth/sample e.g. 24-96, 24/192, 16-44
final _depthRate = RegExp(r'\b(24|16)[ ._/\-]?(44|48|88|96|176|192)\b');
final _hiresTokens =
    RegExp(r'(24[ ._/\-]?bit|\b(88\.2|96|176\.4|192)\s?khz|hi[\- ]?res|hd\s?tracks)', caseSensitive: false);
final _kbps = RegExp(r'\b(320|256|224|192|160|128)\s?k(?:bps)?\b', caseSensitive: false);
final _vx = RegExp(r'\bV([012])\b');

/// Quality from a torrent/release name.
Quality qualityFromName(String name) {
  if (_dsd.hasMatch(name)) return const Quality('DSD', QTier.hires);

  final isFlac = _flac.hasMatch(name);
  if (isFlac || _losslessOther.hasMatch(name)) {
    final fmt = isFlac
        ? 'FLAC'
        : (RegExp(r'\balac\b', caseSensitive: false).hasMatch(name)
            ? 'ALAC'
            : (RegExp(r'\bwav', caseSensitive: false).hasMatch(name) ? 'WAV' : 'Lossless'));
    final dr = _depthRate.firstMatch(name);
    if (_hiresTokens.hasMatch(name) || (dr != null && dr.group(1) == '24')) {
      final tag = dr != null ? '${dr.group(1)}/${dr.group(2)}' : '24-bit';
      return Quality('$fmt $tag', QTier.hires);
    }
    return Quality(fmt, QTier.lossless);
  }

  if (_lossy.hasMatch(name)) {
    final kbps = _kbps.firstMatch(name)?.group(1);
    final v = _vx.firstMatch(name);
    final label = kbps != null
        ? 'MP3 $kbps'
        : (v != null ? 'MP3 V${v.group(1)}' : (RegExp(r'\bmp3\b', caseSensitive: false).hasMatch(name) ? 'MP3' : 'Lossy'));
    return Quality(label, QTier.lossy);
  }
  return const Quality('?', QTier.unknown);
}

/// A sample rate in Hz as the kHz figure people actually say: 44100 → “44.1”, 96000 → “96”.
String _khz(int hz) {
  final k = hz / 1000;
  return k == k.roundToDouble() ? '${k.round()}' : k.toStringAsFixed(1);
}

/// Quality from a Soulseek file's real metadata (falls back to name tokens).
///
/// [sampleRate] and [bitsPerSample] are what a file on your own shelf can tell you and a search
/// result cannot: they come out of the FLAC STREAMINFO block. Where they are known they decide
/// both the label and the tier, because “24/192” is the fact and bytes-per-second is a guess at
/// it — a quiet 24-bit recording and a loud 16-bit one can land on the same bitrate.
Quality qualityFromFile({
  required String name,
  required String ext,
  required bool isFlac,
  int? bitrate,
  int? durationSec,
  int? size,
  bool isVbr = false,
  int? sampleRate,
  int? bitsPerSample,
}) {
  const losslessExt = {'flac', 'alac', 'ape', 'wav', 'wavpack', 'aiff', 'tak', 'tta'};
  if (isFlac || losslessExt.contains(ext)) {
    var kbps = bitrate ?? 0;
    if (kbps <= 0 && durationSec != null && durationSec > 0 && size != null && size > 0) {
      kbps = (size * 8 / durationSec / 1000).round(); // effective bitrate → 16-bit vs hi-res
    }
    final fmt = isFlac ? 'FLAC' : ext.toUpperCase();
    final depth = bitsPerSample ?? 0;
    final rate = sampleRate ?? 0;
    if (depth > 0 && rate > 0) {
      // The definition rather than a threshold: more than 16 bits, or more than a CD's 48 kHz.
      final tier = depth > 16 || rate > 48000 ? QTier.hires : QTier.lossless;
      return Quality('$fmt $depth/${_khz(rate)}', tier);
    }
    final hires = kbps > 1500 || _hiresTokens.hasMatch(name) || (_depthRate.firstMatch(name)?.group(1) == '24');
    // Rate without depth — everything except the FLAC reader is like this. Still worth saying:
    // 96 kHz is the half of the pair that tells you this is not a CD rip.
    if (rate > 0) {
      return Quality('$fmt ${_khz(rate)} kHz', rate > 48000 || hires ? QTier.hires : QTier.lossless);
    }
    if (kbps > 0) return Quality('$fmt · ${kbps}k', hires ? QTier.hires : QTier.lossless);
    return Quality(fmt, hires ? QTier.hires : QTier.lossless);
  }
  final fmt = ext.isEmpty ? 'Audio' : ext.toUpperCase();
  final b = bitrate ?? 0;
  if (b > 0) return Quality('$fmt $b${isVbr ? " VBR" : ""}', QTier.lossy);
  return Quality(fmt, QTier.lossy);
}

/// The filter chips shown above results.
enum QFilter { all, lossless, hires, mp3 }

extension QFilterX on QFilter {
  String get label => switch (this) {
        QFilter.all => 'Alles',
        QFilter.lossless => 'Lossless',
        QFilter.hires => 'Hi-Res',
        QFilter.mp3 => 'MP3',
      };

  bool matches(Quality q) => switch (this) {
        QFilter.all => true,
        QFilter.lossless => q.tier == QTier.lossless || q.tier == QTier.hires,
        QFilter.hires => q.tier == QTier.hires,
        QFilter.mp3 => q.tier == QTier.lossy,
      };
}
