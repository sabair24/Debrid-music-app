/// De cache van nummers op dit toestel: wat de speler helemaal van de pc las, ligt hier; vraagt hij hetzelfde adres
/// opnieuw (herhalen, vorige, een radio die terugkomt), dan komt het van de eigen schijf en niet over je databundel.
///
/// **Waarom (Saber, 27-10-2026).** *"kijk ook eens hoe tidal en Spotify dit doen, om kwaliteit van de liedjes te houden,
/// en toch zuinig te zijn, cache geheugen??"* Ze doen het allebei zo: de app van TIDAL houdt 2 GB, de minst recent
/// gespeelde gaat eerst weg; bij Spotify kwam in hun eigen meting 55 % van wat er speelde uit de cache. In stroom.log
/// van de pc stond die dag Giorgio by Moroder (54 MB) meer dan tien keer vanaf een mobiel adres.
///
/// **De sleutel is het hele adres met de vraag** (`/stream/<id>.flac?maxRate=44100&maxBits=16`): een kopie die onderweg
/// in cd-kwaliteit werd gehaald, past dus nooit op het adres van thuis (het origineel) — de kwaliteit blijft wat je
/// stand vraagt. Alleen `/stream/`; een groeiend nummer (`/groei/`) en een twijfelkopie niet.
///
/// Zonder `package:`-afhankelijkheden en zonder staat in het geheugen: de doorgever draait in een eigen isolate, en elk
/// verzoek kijkt op schijf.
library;

import 'dart:convert';
import 'dart:io';

/// Wat de cache van een adres weet.
typedef Cachestuk = ({File bestand, int totaal, String? etag, String? soort});

class Stroomcache {
  Stroomcache(this.map, {this.maxBytes = kStroomcacheMax, this.maxLeeftijd = const Duration(days: 30)});

  final String map;

  /// Hoeveel er hoogstens ligt; het oudst gespeelde gaat eerst weg.
  final int maxBytes;

  /// Ouder dan dit wordt niet meer gebruikt (en bij het snoeien weggegooid).
  final Duration maxLeeftijd;

  static String _sleutel(String wat) {
    var h = 0x811c9dc5, g = 0x01000193;
    for (final c in utf8.encode(wat)) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
      g = ((g ^ c) * 0x050c5d1f) & 0xffffffff;
    }
    return '${h.toRadixString(16).padLeft(8, '0')}${g.toRadixString(16).padLeft(8, '0')}';
  }

  File _data(String k) => File('$map${Platform.pathSeparator}$k.bin');
  File _meta(String k) => File('$map${Platform.pathSeparator}$k.json');
  File _deel(String k) => File('$map${Platform.pathSeparator}$k.part');

  /// Het complete stuk voor [wat] (pad met vraag), of null. Een treffer telt als gebruik: hij schuift achteraan in de rij
  /// van het snoeien.
  Cachestuk? zoek(String wat) {
    final k = _sleutel(wat);
    try {
      final m = _meta(k), d = _data(k);
      if (!m.existsSync() || !d.existsSync()) return null;
      final j = jsonDecode(m.readAsStringSync());
      if (j is! Map || j['wat'] != wat) return null;
      final totaal = (j['totaal'] as num?)?.toInt() ?? -1;
      if (totaal < 0 || d.lengthSync() != totaal) return null;
      final op = DateTime.fromMillisecondsSinceEpoch((j['op'] as num?)?.toInt() ?? 0);
      if (DateTime.now().difference(op) > maxLeeftijd) return null;
      try {
        d.setLastModifiedSync(DateTime.now());
      } catch (_) {/* dan telt het als ouder; geen ramp */}
      return (bestand: d, totaal: totaal, etag: j['etag'] as String?, soort: j['soort'] as String?);
    } catch (_) {
      return null;
    }
  }

  /// Een nieuw stuk voor [wat]: schrijf erin, en sluit af met [klaar] of [laatVallen].
  IOSink? begin(String wat) {
    try {
      Directory(map).createSync(recursive: true);
      return _deel(_sleutel(wat)).openWrite();
    } catch (_) {
      return null;
    }
  }

  /// [wat] kwam helemaal binnen ([totaal] bytes): bewaren, en daarna snoeien tot onder [maxBytes].
  Future<void> klaar(String wat, IOSink sink, {required int totaal, String? etag, String? soort}) async {
    final k = _sleutel(wat);
    try {
      await sink.flush();
      await sink.close();
      final deel = _deel(k);
      if (deel.lengthSync() != totaal) {
        deel.deleteSync();
        return;
      }
      await deel.rename(_data(k).path);
      await _meta(k).writeAsString(jsonEncode({
        'wat': wat,
        'totaal': totaal,
        if (etag != null) 'etag': etag,
        if (soort != null) 'soort': soort,
        'op': DateTime.now().millisecondsSinceEpoch,
      }));
      snoei();
    } catch (_) {/* dan niet in de cache; de volgende keer opnieuw */}
  }

  /// Niet helemaal binnen (een skip, een spoel, een storing): weg met het halve stuk.
  Future<void> laatVallen(String wat, IOSink sink) async {
    try {
      await sink.close();
    } catch (_) {}
    try {
      final d = _deel(_sleutel(wat));
      if (d.existsSync()) d.deleteSync();
    } catch (_) {}
  }

  /// [wat] klopt niet meer (het nummer veranderde op de pc): weg.
  void vergeet(String wat) {
    final k = _sleutel(wat);
    for (final f in [_data(k), _meta(k)]) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  /// Hoeveel er nu ligt.
  int get grootte {
    var som = 0;
    try {
      for (final e in Directory(map).listSync()) {
        if (e is File && e.path.endsWith('.bin')) som += e.lengthSync();
      }
    } catch (_) {}
    return som;
  }

  /// Het oudst gebruikte weg tot er hoogstens [maxBytes] ligt, en alles ouder dan [maxLeeftijd]; achtergebleven halve
  /// stukken van meer dan een uur oud ook.
  void snoei() {
    try {
      final dir = Directory(map);
      if (!dir.existsSync()) return;
      final nu = DateTime.now();
      final stukken = <(File, int, DateTime)>[];
      for (final e in dir.listSync()) {
        if (e is! File) continue;
        final st = e.statSync();
        if (e.path.endsWith('.part')) {
          if (nu.difference(st.modified) > const Duration(hours: 1)) e.deleteSync();
        } else if (e.path.endsWith('.bin')) {
          stukken.add((e, st.size, st.modified));
        }
      }
      stukken.sort((a, b) => a.$3.compareTo(b.$3));
      var som = stukken.fold(0, (s, x) => s + x.$2);
      for (final (f, n, op) in stukken) {
        if (som <= maxBytes && nu.difference(op) <= maxLeeftijd) continue;
        som -= n;
        f.deleteSync();
        final m = File('${f.path.substring(0, f.path.length - 4)}.json');
        if (m.existsSync()) m.deleteSync();
      }
    } catch (_) {/* de volgende keer */}
  }
}

/// 2 GB, zoals de app van TIDAL: bij cd-kwaliteit ongeveer 70 nummers.
const int kStroomcacheMax = 2 << 30;
