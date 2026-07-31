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

/// Is dit een hi-res bestand? Uit de cijfers van het bestand zelf.
///
/// Voor muziek die HIER staat hoeft er niets geraden te worden: sample rate en bitdiepte staan in de
/// tags en zeggen het precies. [qualityFromFile] raadt uit een naam en een bitrate, en dat moet ook wel
/// bij een release van een vreemde -- maar op de eigen bibliotheek raadde het mis. De titel van een
/// nummer zegt zelden "24bit/96kHz", dus viel élk lokaal nummer in "lossless" en bleef het Hi-Res-filter
/// leeg terwijl er 102 van die nummers stonden.
///
/// De grens ligt op 48 kHz omdat dat is wat een Sonos nog kan; alles daarboven moet door de omzetter.
bool isHiRes({required int sampleRate, required int bitsPerSample}) =>
    sampleRate > 48000 || bitsPerSample > 16;

/// "24/96" -- zoals het op een hoes en in een winkel staat: bitdiepte gedeeld door kHz.
///
/// Voor een hi-res bestand zegt dit meer dan een bitrate. "FLAC · 2973k" is de uitkomst van de muziek
/// én de compressie samen en verschilt per nummer; "24/96" is wat het bestand IS en waar je het aan
/// herkent. Bij cd-kwaliteit is het andersom -- daar is 16/44.1 vanzelfsprekend en zegt de bitrate wél
/// iets -- dus die blijft daar staan.
///
/// De rate met één decimaal als hij niet rond is, want 88.2 en 176.4 zijn geen 88 en 176.
String hiResLabel({required int sampleRate, required int bitsPerSample}) {
  final khz = sampleRate % 1000 == 0
      ? '${sampleRate ~/ 1000}'
      : (sampleRate / 1000).toStringAsFixed(1);
  return '$bitsPerSample/$khz';
}

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

/// Quality from a Soulseek file's real metadata (falls back to name tokens).
Quality qualityFromFile({
  required String name,
  required String ext,
  required bool isFlac,
  int? bitrate,
  int? durationSec,
  int? size,
  bool isVbr = false,
}) {
  const losslessExt = {'flac', 'alac', 'ape', 'wav', 'wavpack', 'aiff', 'tak', 'tta'};
  if (isFlac || losslessExt.contains(ext)) {
    var kbps = bitrate ?? 0;
    if (kbps <= 0 && durationSec != null && durationSec > 0 && size != null && size > 0) {
      kbps = (size * 8 / durationSec / 1000).round(); // effective bitrate → 16-bit vs hi-res
    }
    final fmt = isFlac ? 'FLAC' : ext.toUpperCase();
    final hires = kbps > 1500 || _hiresTokens.hasMatch(name) || (_depthRate.firstMatch(name)?.group(1) == '24');
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
