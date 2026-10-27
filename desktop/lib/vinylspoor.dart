/// Het vinylspoor: een "studio"-kopie die groefruis houdt waar je cd digitaal stil wordt, is een vinylrip.
///
/// Saber, 27-10-2026: *"Kan je onderscheid maken tussen vinyl en studio opname door spectrum?"* — en *"de app analyseert
/// nu toch al of het een echte flac is"*. Ja, maar de echtheidsmeting (echtheid.dart) zoekt nép: een mp3 als FLAC, een
/// opgeschaalde cd. Een vinylrip is eerlijk verliesvrij en klinkt tot ver boven 22 kHz: daar ziet ze terecht niets mis.
/// Het verschil met een studiomaster zit niet in het spectrum als geheel (gemeten: rommel onder 15 Hz, kraak in het hoog
/// en de bas op de zijkant overlappen volledig), maar in de stilte.
///
/// Gemeten op het stilste halve seconde van het hele nummer:
/// * 18 kopieën die zeker digitaal zijn (TIDAL): 17 onder −83,7 dB, de meeste echte digitale stilte. Eén (−51,6 dB)
///   wordt nergens stil — daarom alleen tegenover een digitale kopie van hetzelfde nummer die wél stil wordt.
/// * 18 vinylrips: 13 tussen −42 en −69 dB (groefruis); 5 met stiltes die de ripper dempte (die mist het spoor).
/// * Discovery: zes "studio" 24/96 tussen −51 en −64 dB op momenten waar de cd −200 dB is; vier echte op −145/−200.
///
/// Saber koos: *"Als vinyl behandelen, maar moet niet weg e, want nu heb ik een categorie vinyl"*. Wat het spoor vindt,
/// wordt vinyl; heb je al een vinyl van dat nummer, dan blijft de bewezen betere (één per soort, versie_opbergen.dart).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'ffmpeg.dart';
import 'flac_tags.dart' show readFlacTags;

/// Je digitale kopie zakt hieronder: echte digitale stilte (of dither) ergens in het nummer.
const double kDigitaalStil = -85;

/// De kandidaat komt nergens onder dit: groefruis. Vinyl gemeten tot −69,4, digitaal vanaf −83,7.
const double kGroefruis = -75;

/// Zoveel seconden korter mag de kandidaat zijn — meer, en zijn stille staart kan er gewoon af zijn geknipt.
/// (Too Long, studio-kopie: 1,6 s korter dan de cd.)
const double kKorterMag = 2.0;

/// Het stilste halve seconde van een nummer in dB (−200: digitale stilte), en hoe lang het is.
typedef Stilte = ({double stilste, double seconden});

/// Klinkt [kandidaat] als vinyl, naast [digitaal] — een kopie van hetzelfde nummer waarvan vaststaat dat ze digitaal is
/// (je cd)?
bool klinktAlsVinyl(Stilte kandidaat, Stilte digitaal) =>
    digitaal.stilste < kDigitaalStil &&
    kandidaat.stilste > kGroefruis &&
    kandidaat.seconden >= digitaal.seconden - kKorterMag;

/// Wie het stilste halve seconde van een bestand meet ([Stiltemeter.meet]); null tot de pc hem zet (main.dart) — dan
/// geen vinylspoor, zoals in een toets of op een toestel.
Future<Stilte?> Function(String pad)? stilteVan;

/// Het laagste niveau uit het logboek van ffmpeg (`ametadata=mode=print`), of null als er geen meting in staat.
@visibleForTesting
double? stilsteUitLog(String log) {
  double? laagste;
  for (final m in RegExp(r'RMS_level=(-?[0-9.]+|-inf)').allMatches(log)) {
    final v = m.group(1) == '-inf' ? -200.0 : double.tryParse(m.group(1)!);
    if (v == null) continue;
    final w = v < -200 ? -200.0 : v;
    if (laagste == null || w < laagste) laagste = w;
  }
  return laagste;
}

/// Meet met ffmpeg, per halve seconde over het hele nummer, en onthoudt de uitkomst per pad, grootte en tijd in
/// [bestand] — een decodeerbeurt van een 24/192 duurt seconden, en de opruiming bij de start vraagt het elke keer.
class Stiltemeter {
  Stiltemeter({this.bestand, String? ffmpegPad}) : _ffmpeg = ffmpegPad;

  final String? bestand;
  final String? _ffmpeg;
  final Map<String, Stilte> _geheugen = {};
  bool _geladen = false;
  Timer? _bewaren;

  String _sleutel(String pad, FileStat st) =>
      '${pad.replaceAll('\\', '/').toLowerCase()}|${st.size}|${st.modified.millisecondsSinceEpoch}';

  Future<void> _laad() async {
    if (_geladen) return;
    _geladen = true;
    final b = bestand;
    if (b == null) return;
    try {
      final j = jsonDecode(await File(b).readAsString());
      if (j is! Map) return;
      for (final e in j.entries) {
        final w = e.value;
        if (w is List && w.length == 2) {
          _geheugen['${e.key}'] = (stilste: (w[0] as num).toDouble(), seconden: (w[1] as num).toDouble());
        }
      }
    } catch (_) {
      /* geen of een kapot bestand: opnieuw meten */
    }
  }

  void _bewaarStraks() {
    final b = bestand;
    if (b == null) return;
    _bewaren?.cancel();
    _bewaren = Timer(const Duration(seconds: 5), () async {
      try {
        final tmp = File('$b.tmp');
        await tmp.writeAsString(
          jsonEncode({
            for (final e in _geheugen.entries) e.key: [e.value.stilste, e.value.seconden],
          }),
        );
        await tmp.rename(b);
      } catch (_) {
        /* volgende keer */
      }
    });
  }

  /// Het stilste halve seconde van [pad], of null als het niet te meten is (geen ffmpeg, geen bestand).
  Future<Stilte?> meet(String pad) async {
    await _laad();
    final f = File(pad);
    final FileStat st;
    try {
      st = await f.stat();
      if (st.type != FileSystemEntityType.file) return null;
    } catch (_) {
      return null;
    }
    final k = _sleutel(pad, st);
    final al = _geheugen[k];
    if (al != null) return al;
    final exe = Ffmpeg(pad: _ffmpeg).pad;
    if (exe == null) return null;
    final kop = readFlacTags(f);
    final rate = (kop?.sampleRate ?? 0) > 0 ? kop!.sampleRate : 44100;
    try {
      final p = await Process.start(exe, [
        '-nostdin',
        '-hide_banner',
        '-nostats',
        '-i',
        pad,
        '-af',
        'asetnsamples=n=${rate ~/ 2},astats=metadata=1:reset=1,ametadata=mode=print:key=lavfi.astats.Overall.RMS_level',
        '-f',
        'null',
        '-',
      ]);
      final log = p.stderr.transform(const Utf8Decoder(allowMalformed: true)).join();
      unawaited(p.stdout.drain<void>());
      final code = await p.exitCode.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          p.kill();
          return -1;
        },
      );
      final laagste = stilsteUitLog(await log.timeout(const Duration(seconds: 10), onTimeout: () => ''));
      if (code != 0 || laagste == null) return null;
      final seconden = (kop?.duration?.inMilliseconds ?? 0) / 1000;
      final uit = (stilste: laagste, seconden: seconden);
      _geheugen[k] = uit;
      _bewaarStraks();
      return uit;
    } catch (_) {
      return null;
    }
  }
}
