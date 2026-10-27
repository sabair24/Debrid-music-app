/// De nultoets draaien (nultoets.dart) en onthouden wat hij zei.
///
/// Decoderen met ffmpeg en de FFT's in een eigen isolate: twee keer anderhalve minuut audio en negen FFT's van een
/// miljoen punten is ruim een seconde rekenen, en dat hoort niet op de tekendraad. Eén tegelijk.
///
/// **Onthouden per geluid, niet per pad.** De sleutel is de MD5 van de samples uit de FLAC-kop (plus het aantal): die
/// blijft gelijk als een kopie verhuist naar `_dubbel` of een versiemap, of als het opbergen zijn tags herschrijft — en
/// past nooit op een ander bestand dat later op hetzelfde pad komt. Zonder MD5 (geen FLAC, of een encoder die hem
/// leeg liet): het pad en de grootte.
///
/// [firstIsBetter] is synchroon en mag geen ffmpeg starten: wie een vergelijking voorbereidt, meet eerst
/// ([meetNultoets], versie_opbergen.dart), en de keuring leest daarna alleen ([nultoetsUitslag]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'echtheid_meter.dart' show leesStreaminfo;
import 'ffmpeg.dart';
import 'nultoets.dart';

final Map<String, Nuluitkomst> _uitslagen = {};
final Map<String, String> _idGeheugen = {};
String? _bestand;
Timer? _bewaren;

/// Waar de laatste meting op stukliep (geen ffmpeg-uitvoer, een fout in de isolate). Nooit stil falen.
String? laatsteNultoetsFout;

/// Wie de nultoets meet ([Nultoetser.meet]); null tot de pc hem zet (main.dart) — dan wordt er niets gemeten, zoals in
/// een toets of op een toestel, en telt de diepte nergens (keuring.dart).
Future<Nuloordeel?> Function(String kandidaat, String cd)? meetNultoets;

/// Wat er van dit geluid bekend is: de MD5 van de samples en hun aantal, of het pad en de grootte.
String geluidVan(String pad) {
  String? sleutel;
  try {
    final st = File(pad).statSync();
    sleutel = '${pad.toLowerCase()}|${st.size}|${st.modified.millisecondsSinceEpoch}';
    final al = _idGeheugen[sleutel];
    if (al != null) return al;
  } catch (_) {/* niet te statten: gewoon lezen, en niets onthouden */}
  final i = leesStreaminfo(pad);
  const leeg = '00000000000000000000000000000000';
  final id = i != null && i.md5 != leeg && i.totaal > 0
      ? '${i.md5}:${i.totaal}'
      : '${pad.replaceAll('\\', '/').toLowerCase()}:${sleutel?.split('|')[1] ?? '?'}';
  if (sleutel != null) {
    if (_idGeheugen.length > 4000) _idGeheugen.clear();
    _idGeheugen[sleutel] = id;
  }
  return id;
}

/// De sleutel van het paar: de 24-bitkopie, dan de 16-bitkopie.
String nulSleutel(String kandidaat, String cd) => '${geluidVan(kandidaat)}>${geluidVan(cd)}';

/// Wat de nultoets over [kandidaat] tegen [cd] zei, of null als hij nooit gemeten werd.
Nuluitkomst? nultoetsUitslag(String kandidaat, String cd) => _uitslagen[nulSleutel(kandidaat, cd)];

/// Alle uitslagen, om mee te geven aan een isolate — zie `Voorkennis` in organize.dart.
Map<String, Nuluitkomst> alleNultoetsen() => Map.of(_uitslagen);

/// Onthoud een uitslag (en bewaar, als er een bestand is).
void onthoudNultoets(String kandidaat, String cd, Nuluitkomst u) {
  _uitslagen[nulSleutel(kandidaat, cd)] = u;
  _bewaarStraks();
}

/// Inlezen bij het opstarten op de pc; daarna bewaart elke nieuwe uitslag zich in [bestand].
Future<void> laadNultoetsen(String bestand) async {
  _bestand = bestand;
  try {
    final f = File(bestand);
    if (!await f.exists()) return;
    final j = jsonDecode(await f.readAsString());
    if (j is! Map) return;
    for (final e in j.entries) {
      final w = e.value;
      if (w is! Map) continue;
      final u = Nuluitkomst.values.where((x) => x.name == w['u']).firstOrNull;
      if (u == null) continue;
      _uitslagen['${e.key}'] = u;
      _details['${e.key}'] = {
        for (final d in w.entries)
          if (d.key != 'u') '${d.key}': d.value,
      };
    }
  } catch (_) {/* kapot of leeg: opnieuw meten */}
}

final Map<String, Map<String, Object?>> _details = {};

void _bewaarStraks() {
  final b = _bestand;
  if (b == null) return;
  _bewaren?.cancel();
  _bewaren = Timer(const Duration(seconds: 3), () async {
    try {
      final inhoud = jsonEncode({
        for (final e in _uitslagen.entries) e.key: {'u': e.value.name, ...?_details[e.key]},
      });
      final tmp = File('$b.tmp');
      await tmp.writeAsString(inhoud);
      await tmp.rename(b);
    } catch (_) {/* volgende keer */}
  });
}

/// Tests delen dit proces.
void resetNultoetsVoorTest() {
  _uitslagen.clear();
  _details.clear();
  _idGeheugen.clear();
  _bestand = null;
  _bewaren?.cancel();
  meetNultoets = null;
}

/// Meet met ffmpeg, één paar tegelijk, en onthoudt de uitkomst ([onthoudNultoets]).
class Nultoetser {
  Nultoetser({String? ffmpegPad}) : _ffmpeg = ffmpegPad;
  final String? _ffmpeg;
  Future<void> _rij = Future.value();

  /// De nultoets van [kandidaat] (24 bit) tegen [cd] (16 bit). Null als hij niet te meten is: geen ffmpeg, een andere
  /// bemonstering (dan zegt een rest niets meer — het omzetten zelf laat er een achter), of te kort.
  Future<Nuloordeel?> meet(String kandidaat, String cd) {
    final klaar = Completer<Nuloordeel?>();
    _rij = _rij.then((_) async {
      try {
        klaar.complete(await _meet(kandidaat, cd));
      } catch (e) {
        laatsteNultoetsFout = '$kandidaat: $e';
        klaar.complete(null);
      }
    });
    return klaar.future;
  }

  Future<Nuloordeel?> _meet(String kandidaat, String cd) async {
    final exe = Ffmpeg(pad: _ffmpeg).pad;
    if (exe == null) return null;
    final a = leesStreaminfo(kandidaat), b = leesStreaminfo(cd);
    if (a != null && b != null && a.sr != b.sr) return null;
    final rate = b?.sr ?? a?.sr ?? kNulRate;
    final seconden = b != null && b.totaal > 0 ? b.totaal / rate : 240.0;
    final plekken = meetplekken(seconden);
    if (plekken.length < 2) return null;
    final tot = plekken.last + kStukSeconden + kZoekSeconden + 2;
    final o = await _inIsolate(exe, kandidaat, cd, plekken, tot);
    if (o == null) return null;
    final s = nulSleutel(kandidaat, cd);
    _details[s] = {
      'k': kandidaat,
      'c': cd,
      'p': [
        for (final p in o.punten)
          [p.verschuiving, _rond(p.versterkingDb), _rond(p.restDb), _rond(p.restDbfs)],
      ],
      't': DateTime.now().millisecondsSinceEpoch,
    };
    onthoudNultoets(kandidaat, cd, o.uitkomst);
    return o;
  }
}

double? _rond(double x) => x.isFinite ? (x * 10).round() / 10 : null;

/// De isolate, vanuit een functie op het hoogste niveau: een closure die in een methode ontstaat, neemt `this` mee — en
/// daarmee [Nultoetser._rij], een Future, en die is niet te verzenden (de hoesveger, 3.9.538).
Future<Nuloordeel?> _inIsolate(String exe, String kandidaat, String cd, List<int> plekken, int tot) =>
    Isolate.run(() => _meetBuiten(exe, kandidaat, cd, plekken, tot));

/// In de isolate: decoderen en meten.
Future<Nuloordeel?> _meetBuiten(String exe, String kandidaat, String cd, List<int> plekken, int tot) async {
  final a = await _decodeer(exe, kandidaat, tot), b = await _decodeer(exe, cd, tot);
  if (a == null || b == null) return null;
  return nultoetsOp(a, b, plekken);
}

/// Mono, [kNulRate], 32-bit float, de eerste [tot] seconden.
Future<Float32List?> _decodeer(String exe, String pad, int tot) async {
  try {
    final r = await Process.run(
        exe,
        [
          '-v', 'error', '-nostdin', '-i', pad, '-t', '$tot', '-map', '0:a:0', //
          '-ac', '1', '-ar', '$kNulRate', '-f', 'f32le', '-',
        ],
        stdoutEncoding: null,
        stderrEncoding: const Utf8Codec(allowMalformed: true));
    if (r.exitCode != 0) return null;
    final bytes = Uint8List.fromList(r.stdout as List<int>);
    return bytes.buffer.asFloat32List(0, bytes.length ~/ 4);
  } catch (_) {
    return null;
  }
}
