/// De decodeerproef op schijf: ffmpeg decodeert het HELE bestand, en de uitslag blijft bewaard.
///
/// **Waarom decoderen en niet de kop lezen.** Elke lengte in de app kwam uit de kop, en een afgekapte
/// FLAC belooft in zijn kop gewoon de volle lengte. Gemeten op 29-09-2026: Lady Gaga — Just Dance zegt
/// 242,8 s en speelt er 192,9; Stromae — Sommeil zegt 218,7 en speelt 0,1. Alleen decoderen ziet dat.
/// Het kost weinig: een FLAC van acht minuten in 24/96 is in 0,2 tot 0,4 s gedecodeerd.
///
/// Het oordeel zelf staat in [beoordeelDecode] (keuring.dart), zuiver en getoetst; hier staat alleen het
/// draaien van ffmpeg en het onthouden.
///
/// **Onthouden op pad, grootte en tijdstempel.** Een bestand dat op hetzelfde pad door een ander wordt
/// vervangen, krijgt zo vanzelf een nieuwe proef — het oude antwoord hoort bij het oude bestand.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ffmpeg.dart';
import 'keuring.dart';
import 'paths.dart';

final Map<String, Heelheid> _uitslagen = {};
bool _geladen = false;
Future<void>? _laden;

/// Wat er de laatste keer misging bij het lezen of bewaren, of null.
String? laatsteIntegriteitFout;

String _sleutelVan(String pad, FileStat st) =>
    '${pad.toLowerCase()}|${st.size}|${st.modified.millisecondsSinceEpoch}';

File get _bestand => File('$appDir${Platform.pathSeparator}integriteit.json');

Future<void> _laad() => _laden ??= () async {
      if (_geladen) return;
      try {
        final f = _bestand;
        if (await f.exists()) {
          final j = jsonDecode(await f.readAsString());
          if (j is Map) {
            for (final e in j.entries) {
              final v = e.value;
              if (v is Map && v['h'] is bool) {
                _uitslagen['${e.key}'] = (heel: v['h'] as bool, reden: v['r'] as String?);
              }
            }
          }
        }
      } catch (e) {
        laatsteIntegriteitFout = 'integriteit.json niet te lezen: $e';
      }
      _geladen = true;
    }();

Future<void> _bewaar() async {
  try {
    // Een bovengrens: dit is een geheugen, geen archief. Wat eruit valt wordt gewoon opnieuw gemeten.
    while (_uitslagen.length > 6000) {
      _uitslagen.remove(_uitslagen.keys.first);
    }
    final inhoud = jsonEncode({
      for (final e in _uitslagen.entries) e.key: {'h': e.value.heel, if (e.value.reden != null) 'r': e.value.reden},
    });
    final tmp = File('${_bestand.path}.tmp');
    await tmp.writeAsString(inhoud, flush: true);
    await tmp.rename(_bestand.path);
  } catch (e) {
    laatsteIntegriteitFout = 'integriteit.json niet te bewaren: $e';
  }
}

/// Kapot volgens een eerdere proef op dít bestand (zelfde grootte en tijdstempel)?
///
/// Alleen wat bewezen is: een nooit gecontroleerd bestand is niet kapot. Zelfde afspraak als
/// `bewezenNep`, en om dezelfde reden — anders herordent een veegbeurt de halve bibliotheek.
bool bekendKapot(String pad) {
  try {
    final st = File(pad).statSync();
    return _uitslagen[_sleutelVan(pad, st)]?.heel == false;
  } catch (_) {
    return false;
  }
}

/// De paden (klein geschreven) van alles wat bewezen kapot is, voor een isolate — die begint met een
/// lege kopie van deze kaart. Zie `Voorkennis` in organize.dart.
Set<String> kapotSleutels() => {
      for (final e in _uitslagen.entries)
        if (!e.value.heel) e.key.substring(0, e.key.indexOf('|')),
    };

/// Het bestand is verplaatst; de uitslag verhuist mee. Uit `_move` in organize.dart, net als de meting
/// en de handmatige keuze.
void herNoemIntegriteit(String van, String naar) {
  final voor = '${van.toLowerCase()}|';
  final sleutels = [for (final k in _uitslagen.keys) if (k.startsWith(voor)) k];
  if (sleutels.isEmpty) return;
  for (final k in sleutels) {
    final u = _uitslagen.remove(k)!;
    _uitslagen['${naar.toLowerCase()}${k.substring(voor.length - 1)}'] = u;
  }
  unawaited(_bewaar());
}

/// Formaten waarvan de kop een EXACTE lengte draagt. Bij een mp3 zonder Xing-kop schat ffmpeg de
/// lengte uit de bestandsgrootte, en dan is "korter dan de kop" geen bewijs van iets.
bool _kopIsExact(String pad) {
  final p = pad.toLowerCase();
  return const ['.flac', '.wv', '.ape', '.wav', '.aiff', '.aif', '.tta', '.tak']
      .any(p.endsWith);
}

final RegExp _duurRegel = RegExp(r'Duration:\s*(\d+):(\d\d):(\d\d(?:\.\d+)?)');

/// Decodeer [pad] helemaal en zeg of het heel is. Null als het niet te zeggen valt: geen ffmpeg, het
/// bestand is weg, of de proef liep uit de tijd — en niet te zeggen is nooit een reden om te weigeren.
Future<Heelheid?> controleerHeel(String pad, {Duration limiet = const Duration(minutes: 3)}) async {
  final f = File(pad);
  FileStat st;
  try {
    st = await f.stat();
    if (st.type != FileSystemEntityType.file) return null;
  } catch (_) {
    return null;
  }
  await _laad();
  final sleutel = _sleutelVan(pad, st);
  final bekend = _uitslagen[sleutel];
  if (bekend != null) return bekend;
  final ffmpeg = Ffmpeg().pad;
  if (ffmpeg == null) return null;

  Process? p;
  try {
    // level+info: elke regel draagt zijn niveau, zodat "[error]" en de "Duration:"-regel uit één run
    // komen. `-map 0:a:0?`: alleen het geluid — een ingebed hoesje geeft anders zijn eigen gemopper
    // ("Could not read mimetype"), en dat zegt niets over de muziek.
    p = await Process.start(ffmpeg, [
      '-nostdin', '-hide_banner', '-loglevel', 'level+info', //
      '-i', pad, '-map', '0:a:0?', '-f', 'null', '-', '-progress', 'pipe:1', '-nostats',
    ]);
    final fouten = <String>[];
    double? kop;
    int? uitUs;
    final klaarErr = p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((r) {
      if (r.contains('[error]') || r.contains('[fatal]')) fouten.add(r);
      final m = _duurRegel.firstMatch(r);
      if (m != null && kop == null) {
        kop = int.parse(m.group(1)!) * 3600 + int.parse(m.group(2)!) * 60 + double.parse(m.group(3)!);
      }
    }).asFuture<void>();
    final klaarOut = p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((r) {
      if (r.startsWith('out_time_us=')) uitUs = int.tryParse(r.substring(12)) ?? uitUs;
    }).asFuture<void>();
    final code = await p.exitCode.timeout(limiet);
    await Future.wait([klaarErr, klaarOut]).timeout(const Duration(seconds: 5), onTimeout: () => const []);
    final u = beoordeelDecode(
      exitCode: code,
      foutregels: fouten,
      kopSeconden: _kopIsExact(pad) ? kop : null,
      gedecodeerdSeconden: uitUs == null ? null : uitUs! / 1e6,
    );
    _uitslagen[sleutel] = u;
    unawaited(_bewaar());
    return u;
  } on TimeoutException {
    p?.kill();
    return null;
  } catch (e) {
    laatsteIntegriteitFout = 'decodeerproef mislukt: $e';
    return null;
  }
}

/// Tests delen dit proces.
void resetIntegriteitVoorTest() {
  _uitslagen.clear();
  _geladen = false;
  _laden = null;
  laatsteIntegriteitFout = null;
}

/// Voor een toets: een uitslag neerzetten zonder ffmpeg.
void zetIntegriteitVoorTest(String pad, Heelheid h) {
  final st = File(pad).statSync();
  _uitslagen[_sleutelVan(pad, st)] = h;
  _geladen = true;
}
