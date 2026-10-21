/// Is een binnengekomen bestand de VERSIE die gevraagd werd — en niet de albumversie onder de naam
/// "(Acoustic)", of een live-opname, of een versnelde?
///
/// Saber, 21-10-2026, over "Light Switch (Acoustic)" van de Sabrina-radio: *"die vingerafdruk ? hoe doen we
/// dit, want acoustid werkt langs geen kanten … die herkend totaal men liedjes niet !!!"* AcoustID moet een
/// nummer OPZOEKEN in een gedeelde databank, en die kent zijn nummers niet. Dat is hier niet nodig: we weten
/// welke versie we vroegen, en Deezer laat van precies die versie 30 seconden horen. Dus: het fragment over
/// het hele bestand schuiven ([fragmentOvereenkomst]) en kijken of het past.
///
/// Geijkt op 21-10-2026 op dertig nummers uit Sabers bibliotheek (63 paren): de gevraagde versie 0,935–0,987
/// (29 van 30 — de dertigste was het foute Light Switch-bestand, 0,642); een andere opname (akoestisch, live,
/// versneld, vertraagd, de meeste remixen) 0,53–0,72. Remixen die in het fragment dezelfde opname gebruiken,
/// halen 0,84–0,97: die vallen er niet mee te vangen.
///
/// "Geen oordeel is ja", zoals elders in de keuring: geen fpcalc, geen Deezer-nummer, geen fragment, geen net
/// — dan weigert dit niets.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'deezerbaan.dart';
import 'fingerprint.dart';
import 'organize.dart' show artistKey, normKey;
import 'paths.dart';

/// Onder deze overeenkomst is het een andere opname: weigeren, de volgende uploader.
const double kAndereVersieOnder = 0.80;

/// Vanaf deze overeenkomst is het dezelfde opname. Daartussen: twijfel (gehouden, en opgeschreven).
const double kZelfdeVersieVanaf = 0.93;

String _zonderGast(String t) => t
    .replaceAll(RegExp(r'\s*[\(\[]\s*(feat\.?|ft\.?|featuring|with)\s[^\)\]]*[\)\]]', caseSensitive: false), '')
    .trim();

/// Het Deezer-nummer dat werkelijk [titel] van [artiest] is, met een fragment — of null.
///
/// De artiest moet kloppen (of de artiest in het bestand begint met die van Deezer: een samenwerking), de
/// titel precies of zonder gastrol, en de lengte op drie seconden als die bekend is.
Map<String, dynamic>? kiesDeezerNummer(List<dynamic> data, String artiest, String titel, int? seconden) {
  final wilTitel = normKey(titel);
  final wilKaal = normKey(_zonderGast(titel));
  final wilArtiest = artistKey(artiest);
  if (wilTitel.isEmpty || wilArtiest.isEmpty) return null;
  for (final d in data) {
    if (d is! Map<String, dynamic>) continue;
    final art = d['artist'];
    final k = artistKey('${art is Map ? art['name'] ?? '' : ''}');
    if (k.isEmpty || !(k == wilArtiest || wilArtiest.startsWith('$k '))) continue;
    final t = '${d['title'] ?? ''}';
    if (normKey(t) != wilTitel && normKey(_zonderGast(t)) != wilKaal) continue;
    final duur = (d['duration'] as num?)?.toInt();
    if (seconden != null && seconden > 0 && duur != null && (duur - seconden).abs() > 3) continue;
    if ('${d['preview'] ?? ''}'.isEmpty) continue;
    return d;
  }
  return null;
}

class Versiecontrole {
  Versiecontrole({Fingerprinter? vingerafdruk}) : _fp = vingerafdruk ?? Fingerprinter();

  final Fingerprinter _fp;

  Directory get _map => Directory('$appDir${Platform.pathSeparator}fragmenten');

  /// Per gevraagd nummer één zoektocht: een race probeert soms vijf uploaders na elkaar.
  static final _fragmenten = <String, Future<String?>>{};

  /// Zoveel fragmenten blijven op schijf (een half megabyte elk); de oudste gaan eerst.
  static const _maxFragmenten = 300;

  /// De overeenkomst van [pad] met het Deezer-fragment van [titel] van [artiest], of null als dat niet te
  /// zeggen is.
  Future<double?> score(String pad, {required String artiest, required String titel, int? seconden}) async {
    try {
      final fragment = await _fragment(artiest, titel, seconden);
      if (fragment == null) return null;
      final heel = await _fp.of(pad, heel: true);
      final kort = await _fp.of(fragment, heel: true);
      if (heel == null || kort == null || heel.raw.isEmpty || kort.raw.isEmpty) return null;
      return fragmentOvereenkomst(heel.raw, kort.raw);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fragment(String artiest, String titel, int? seconden) {
    final sleutel = '${artistKey(artiest)}|${normKey(titel)}|${seconden ?? ''}';
    return _fragmenten[sleutel] ??= _haalFragment(artiest, titel, seconden).then((pad) {
      // Niets gevonden of geen net: de volgende keer opnieuw proberen.
      if (pad == null) _fragmenten.remove(sleutel);
      return pad;
    });
  }

  Future<String?> _haalFragment(String artiest, String titel, int? seconden) async {
    try {
      final j = await DeezerBaan.haal(
          'https://api.deezer.com/search?q=${Uri.encodeComponent('$artiest $titel')}&limit=15');
      final d = kiesDeezerNummer((j?['data'] as List?) ?? const [], artiest, titel, seconden);
      if (d == null) return null;
      final f = File('${_map.path}${Platform.pathSeparator}${d['id']}.mp3');
      if (await f.exists() && await f.length() > 50000) return f.path;
      final r = await http.get(Uri.parse('${d['preview']}')).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200 || r.bodyBytes.length < 50000) return null;
      await _map.create(recursive: true);
      await f.writeAsBytes(r.bodyBytes, flush: true);
      unawaited(_snoei());
      return f.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _snoei() async {
    try {
      final alle = [for (final e in _map.listSync()) if (e is File && e.path.endsWith('.mp3')) e];
      if (alle.length <= _maxFragmenten) return;
      alle.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
      for (final f in alle.take(alle.length - _maxFragmenten)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    } catch (_) {/* opruimen is geen reden om iets te laten mislukken */}
  }
}
