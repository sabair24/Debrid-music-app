/// Hoeveel een Soulseek-zoekvraag mag terugbrengen, en welke vraag een album het best vindt.
///
/// **Waarom.** Saber, 15-10-2026: de app crashte op de albumpagina van Live — *V* (2001). De
/// albumbrede vraag was "Live V". Soulseek negeert een woord van één letter, dus dat werd in feite
/// "live": 60.919 bestanden, 18 MB, van iedereen die ooit een live-opname deelde (gemeten via
/// `/api/soulseek/search`). De pc stond 4 tot 6 seconden stil om dat om te zetten (hartslag.log:
/// "HAPERING 6.4 s"), en de gsm kreeg die 18 MB binnen en zeefde ze per nummer opnieuw.
///
/// Twee reparaties, allebei hier:
/// - [beperkZoekuitslag]: nooit meer dan [kZoekPlafond] bestanden. Welke blijven, beslist hoeveel
///   woorden van de VRAAG in het pad staan, ook die van één letter: de map `Live\V (2001)` heeft er
///   drie, `Iemand\Live at Wembley` één.
/// - [albumZoekvraag]: noemt de albumtitel geen enkel woord dat Soulseek meetelt, dan gaat het jaar
///   mee. "Live V 2001" vindt de map `V (2001)`; "Live V" vond alleen "live".
library;

import 'audioformaten.dart' show isVerliesvrij;
import 'quality.dart' show capaciteitOpEenSchaal, effectieveBitrate, kwaliteitsRang;
import 'soulseek.dart';

/// Ruim boven een gewone albumvraag: een volledig album gaf er 4400 (11-10-2026), een nummer 1424.
const kZoekPlafond = 5000;

final _scheiding = RegExp(r'[^a-z0-9]+');

Set<String> _woorden(String s) => s.toLowerCase().split(_scheiding).where((w) => w.isNotEmpty).toSet();

/// Hoeveel woorden van de vraag als heel woord in [pad] staan.
int zoekRelevantie(Set<String> vraagWoorden, String pad) {
  final p = _woorden(pad);
  var n = 0;
  for (final w in vraagWoorden) {
    if (p.contains(w)) n++;
  }
  return n;
}

/// Hoogstens [plafond] bestanden: de best passende, daarbinnen de best klinkende ([zoekKwaliteit]), en dan in de
/// volgorde die ze hadden (`sortSoulseek`: FLAC en snelle peers eerst). Onder het plafond verandert er niets, ook de
/// volgorde niet.
///
/// **De kwaliteit erbij (Saber, 24-10-2026):** *"voor het zelfde geldt zijn er voorbij die 5000 resultaten wel goeie
/// kwaliteit tussen"*. Bij gelijke pasvorm keek dit alleen naar de volgorde van `sortSoulseek`, en daar wint binnen
/// FLAC wie een vrije plek en een snelle lijn heeft — een hi-res kopie bij een trage peer kon zo afvallen terwijl een
/// cd-kopie bleef. Nu valt bij gelijke pasvorm altijd het slechtst klinkende af.
List<SoulseekFile> beperkZoekuitslag(String vraag, List<SoulseekFile> files, {int plafond = kZoekPlafond}) {
  if (files.length <= plafond) return files;
  final vw = _woorden(vraag);
  final score = [for (final f in files) zoekRelevantie(vw, f.filename)];
  final klank = [for (final f in files) zoekKwaliteit(f)];
  final volgorde = List<int>.generate(files.length, (i) => i)
    ..sort((a, b) {
      final s = score[b].compareTo(score[a]);
      if (s != 0) return s;
      final k = klank[b].compareTo(klank[a]);
      return k != 0 ? k : a.compareTo(b);
    });
  return [for (final i in volgorde.take(plafond)) files[i]];
}

/// Hoe goed [f] klinkt volgens wat de peer meldt: verliesvrij boven lossy, daarbinnen bemonstering × bitdiepte (of de
/// bitrate als hij die niet meldt). Dezelfde maat als de zoeklijst (`_slskRang` in main.dart): [kwaliteitsRang] met
/// [capaciteitOpEenSchaal].
int zoekKwaliteit(SoulseekFile f) {
  final lossless = isVerliesvrij(f.ext);
  final kbps = effectieveBitrate(bitrate: f.bitrate, durationSec: f.durationSec, size: f.size);
  return kwaliteitsRang(
      lossless: lossless,
      kbps: capaciteitOpEenSchaal(sampleRate: f.sampleRate, bitDepth: f.bitDepth, kbps: kbps, lossless: lossless));
}

/// Een woord dat Soulseek meetelt: twee tekens of meer. Zie [albumZoekvraag].
bool _telt(String w) => w.length > 1;

/// De vraag waarmee een hele plaat gezocht wordt: artiest en titel, en het jaar als de titel zelf
/// niets zegt. "V", "X" of "4" zijn voor Soulseek geen woord; zonder jaar blijft alleen de artiest
/// over, en bij een artiest als Live is dat elke live-opname ter wereld.
String albumZoekvraag(String artiest, String album, {int? jaar}) {
  final basis = '$artiest $album'.trim().replaceAll(RegExp(r'\s+'), ' ');
  final titelTelt = album.toLowerCase().split(_scheiding).any(_telt);
  if (titelTelt || jaar == null || jaar < 1000) return basis;
  return '$basis $jaar';
}
