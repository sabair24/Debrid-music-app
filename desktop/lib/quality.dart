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

/// De bitrate waar je op af kunt gaan: wat de peer meldt, of anders wat grootte en duur zeggen.
///
/// Soulseek-peers laten de bitrate geregeld weg, en juist bij een FLAC is dat het getal dat telt: bij
/// lossless is de bitrate recht evenredig met wat er in het bestand zit. 6511k is 24/192, rond de 2900k
/// is 24/96, rond de 1000k is cd. Grootte gedeeld door speelduur geeft precies datzelfde getal, dus een
/// ontbrekende melding is geen reden om een bestand als "onbekend" onderaan te laten belanden.
int effectieveBitrate({int? bitrate, int? durationSec, int? size}) {
  if (bitrate != null && bitrate > 0) return bitrate;
  if (durationSec != null && durationSec > 0 && size != null && size > 0) {
    return (size * 8 / durationSec / 1000).round();
  }
  return 0;
}

/// Meer dan twee kanalen — uitgerekend, niet geraden.
///
/// Een FLAC is nooit gróter dan onbewerkt; comprimeren maakt kleiner. Onbewerkt stereo is
/// `sampleRate × bits × 2`, dus een bestand dat daar overheen gaat kan onmogelijk stereo zijn: het heeft
/// meer kanalen. Dat is geen aanwijzing maar een tegenspraak.
///
/// Waarom dit ertoe doet: een 5.1-mix wordt op een stereo-installatie teruggemengd, en is dan mínder dan
/// een gewone stereomix — terwijl hij véél groter is en dus bovenaan elke lijst op grootte belandt. De
/// naam verraadt hem lang niet altijd; dit wel.
///
/// Voorbeeld uit de eigen zoekresultaten: een bestand dat 24/96 meldt en 10958 kbit/s meet. Onbewerkt
/// stereo is daar 4608 kbit/s. Dat kán niet, dus het is meerkanaals — en het stond bovenaan.
///
/// Null-veilig: zonder sample rate of bitdiepte valt er niets te bewijzen en is het antwoord `false`.
/// De naamherkenning blijft daarnaast bestaan voor precies dat geval.
bool meerDanStereo({int? sampleRate, int? bitDepth, required int kbps}) {
  if (sampleRate == null || bitDepth == null || sampleRate <= 0 || bitDepth <= 0 || kbps <= 0) {
    return false;
  }
  final onbewerktStereo = sampleRate * bitDepth * 2 / 1000;
  return kbps > onbewerktStereo;
}

/// Verdacht klein voor wat het bewéért — een AANWIJZING, geen tegenspraak.
///
/// Bij een zoekresultaat is meten onmogelijk: je kunt niet in het bestand van een vreemde kijken zonder
/// het eerst binnen te halen. Wat wél kan is de getallen tegen elkaar wegstrepen die de peer zelf
/// meestuurt. Een 24/96 die uit een 44,1 kHz-bron is opgetild draagt alleen de inhoud van die bron, en
/// pakt dus veel kleiner in dan een echte 24/96.
///
/// De verhouding is aan echte bestanden uit deze bibliotheek gemeten en staat hierboven bij
/// [capaciteitOpEenSchaal]: een echte lossless zit rond .65 van onbewerkt stereo (.69, .70, .59, .69).
/// Een opgeblazen bestand zakt naar .25 à .35. De drempel ligt op **.40**, ruim onder de laagste echte
/// meting van .59 — een stille solopiano op 24/96 comprimeert ook goed, en die mag hier niet in vallen.
///
/// ALLEEN bij geclaimde hi-res. Bij 16/44,1 zegt de verhouding niets: een transcode van 320 kbps terug
/// naar 16-bit FLAC pakt ongeveer even goed in als het origineel, soms zelfs slechter — gemeten kwam een
/// transcode op 76 MB uit waar het origineel 34 MB was. Daar helpt alleen de spectrale meting ná
/// binnenkomst.
///
/// Dit hoort NIET in de rangschikking. [meerDanStereo] zit daar wel in omdat het een bewijs is; dit is
/// een vermoeden, en een vermoeden hoort de gebruiker te informeren, niet voor hem te beslissen.
bool verdachtKleinVoorHiRes({int? sampleRate, int? bitDepth, required int kbps}) {
  if (sampleRate == null || bitDepth == null || kbps <= 0) return false;
  if (!isHiRes(sampleRate: sampleRate, bitsPerSample: bitDepth)) return false;
  final onbewerktStereo = sampleRate * bitDepth * 2 / 1000;
  if (onbewerktStereo <= 0) return false;
  return kbps / onbewerktStereo < 0.40;
}

/// Eén getal voor "hoeveel muziek zit hierin", ook als de peer het formaat niet meldt.
///
/// Zonder dit worden twee verschillende dingen met elkaar vergeleken. Meldt de peer 24/192, dan wordt er
/// op `sampleRate × bitDepth` afgerekend: 4608, de RUWE capaciteit. Meldt hij niets, dan blijft alleen de
/// gemeten bitrate over, en dat is wat het INGEPAKTE bestand gebruikt — ongeveer tweederde daarvan. Elk
/// bestand waarvan we het formaat niet kennen staat daardoor stelselmatig te hoog: een onbekende cd-rip
/// komt op 900 uit tegen 705 voor een gemelde 16/44.1, en wint dus van zijn eigen gelijke.
///
/// De verhouding is gemeten aan echte bestanden uit deze bibliotheek: 32/384 kwam op .69 en .70 uit,
/// 24/192 op .59, 24/96 op .69 — samen rond de .65 van onbewerkt stereo. Delen door `2 × .65` brengt een
/// gemeten bitrate dus terug op dezelfde schaal als een gemeld formaat.
///
/// Het blijft een schatting, en dat mag: het gaat om de volgorde, niet om het getal. Wat het weghaalt is
/// de voorsprong die "onbekend" nu cadeau krijgt — precies omgekeerd aan wat je wilt.
///
/// Voor lossy heeft ruwe capaciteit geen betekenis. Daar is de bitrate zelf het getal dat telt, en die
/// blijft staan; lossy zit toch al in een lagere laag van [kwaliteitsRang].
int capaciteitOpEenSchaal(
    {int? sampleRate, int? bitDepth, required int kbps, required bool lossless}) {
  if (sampleRate != null && bitDepth != null && sampleRate > 0 && bitDepth > 0) {
    return sampleRate * bitDepth ~/ 1000;
  }
  if (!lossless || kbps <= 0) return kbps;
  return (kbps / 1.3).round();
}

/// Waar een bestand in de rangschikking komt: hoger is beter.
///
/// Drie lagen, van zwaar naar licht.
///
/// **Stereo boven surround**, en dat is de zwaarste. Een 5.1-bestand is groot omdat het zes kanalen
/// draagt, niet omdat het beter klinkt — op een stereo-installatie wordt het teruggemengd, en dan heb je
/// een enorm bestand dat mínder is dan een gewone stereomix. Op bitrate alleen sorteren zet het dus
/// precies verkeerd om: hoe onbruikbaarder, hoe hoger. Wie stereo wil, wil ze allemaal eerst zien.
///
/// **Lossless boven lossy.** Geen enkele mp3 haalt een FLAC in: een 320k mp3 hoort onder een 900k FLAC.
///
/// **Dan pas de bitrate.** Binnen dezelfde soort is dat recht evenredig met wat erin zit.
///
/// De sprongen zijn zo groot dat een laag nooit door de laag eronder ingehaald kan worden, ook niet door
/// de hoogste bitrate die bestaat.
int kwaliteitsRang({required bool lossless, required int kbps, bool stereo = true}) =>
    (stereo ? 100000000 : 0) + (lossless ? 1000000 : 0) + kbps;

/// "24/96" of "16/44.1" -- zoals het op een hoes en in een winkel staat: bitdiepte gedeeld door kHz.
///
/// Voor ELK lossless bestand, niet alleen voor hi-res. Een bitrate is de uitkomst van de muziek én de
/// compressie samen en verschilt per nummer -- twee nummers van hetzelfde album geven andere getallen --
/// terwijl dit zegt wat het bestand IS. En één notatie voor de hele lijst leest rustiger dan een kolom
/// waarin de ene rij "2973k" zegt en de andere "24/96": dan vergelijk je appels met peren.
///
/// Voor MP3 heeft dit geen betekenis; daar blijft de bitrate het getal dat ertoe doet.
///
/// De rate met één decimaal als hij niet rond is, want 88.2 en 176.4 zijn geen 88 en 176.
String depthRateLabel({required int sampleRate, required int bitsPerSample}) {
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
