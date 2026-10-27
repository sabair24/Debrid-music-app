/// Dataverbruik: wat dit toestel over het netwerk haalt — per dag, per soort netwerk (mobiel of wifi) en per soort
/// verkeer — met een logboek erbij.
///
/// **Waarom dit bestaat.** Saber, 27-10-2026: *"derna moeten we eens echt kijken naar men data verbruik buitenshuis,
/// via mobile internet, want die is echt nog veel. ik wil een volledige analyse, de app moet vanaf nu alles bijhouden in
/// een log, plus ik wil bij instellingen, sectie info wat men data verbruik is"*. Tot dan wist de app het niet:
/// `stroom.log` op de pc noemt de grootte van wat hij aanbood, niet wat er over de lijn ging, en van de catalogus en de
/// hoezen stond nergens iets.
///
/// Twee bronnen, en ze vullen elkaar aan:
/// * **Android zelf** ([androidVerbruik]): wat het systeem voor deze app telt, mobiel en wifi apart — hetzelfde getal
///   als in Instellingen › Verbindingen › Dataverbruik, met alles erin (ook wat mpv binnenhaalt).
/// * **De app** ([DataverbruikStore.tel]): waar het heen ging — muziek, hoezen, de catalogus, de rest van de pc, en
///   diensten op het internet. Geteld waar de bytes langskomen: de doorgever (alle muziek en hoezen voor mpv), en de
///   aanvragen bij de pc.
///
/// Het logboek (`verbruik.log`) krijgt elke grote haal (een nummer) met zijn naam, en elk kwartier een samenvatting; de
/// regels gaan ook naar de pc (`verbruik.log` daar), zodat ze te lezen zijn terwijl de telefoon onderweg is.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'netsoort.dart';

/// Waar de bytes heen gingen.
enum Verkeerssoort {
  /// Nummers: `/stream/` en `/groei/` van de pc (en wat de telefoon vooruit binnenhaalt).
  muziek,

  /// Hoezen en artiestfoto's van de pc.
  hoezen,

  /// De catalogus van de pc (`/api/catalog`).
  catalogus,

  /// Zones en de gedeelde staat: de gebeurtenissenstroom (`/api/zones/events`), de stand en de wachtrij (`/api/state`).
  zones,

  /// Al de rest bij de pc: zoeken, de wachtrij, zones, gedeelde staat, logboeken.
  pc,

  /// Diensten op het internet: Deezer, Last.fm, foto's, het bijwerken van de app.
  buiten,
}

/// De soort van een aanvraag naar [pad] (het pad van het adres). [vanDePc]: het adres is de pc (of de doorgever, die
/// voor de pc staat).
Verkeerssoort soortVanPad(String pad, {required bool vanDePc}) {
  if (!vanDePc) return Verkeerssoort.buiten;
  if (pad.startsWith('/stream/') || pad.startsWith('/groei/')) return Verkeerssoort.muziek;
  if (pad.startsWith('/art') || pad.startsWith('/api/artist-art') || pad.contains('/foto')) return Verkeerssoort.hoezen;
  if (pad.startsWith('/api/catalog')) return Verkeerssoort.catalogus;
  if (pad.startsWith('/api/zones') || pad.startsWith('/api/state')) return Verkeerssoort.zones;
  return Verkeerssoort.pc;
}

/// Wat een adres van de doorgever (`/stream/<id>.flac?maxRate=…`) speelt, voor de regel in het logboek: "Foreigner – I
/// Want to Know What Love Is (met plafond)". [nummers]: de bibliotheek, met paden als `http://pc.invalid/stream/<id>.flac`.
/// Het pad zelf als het nummer niet te vinden is.
String stroomNaam(Iterable<({String pad, String naam})> nummers, String pad) {
  final m = RegExp(r'^/(?:stream|groei|kandidaat)/([^/?.]+)').firstMatch(pad);
  final plafond = pad.contains('maxRate=') || pad.contains('maxBits=') ? ' (met plafond)' : '';
  final id = m?.group(1);
  if (id == null) return pad;
  final sleutel = '/stream/$id.';
  for (final t in nummers) {
    if (t.pad.contains(sleutel)) return '${t.naam}$plafond';
  }
  return '${pad.split('?').first}$plafond';
}

/// "33,9 MB", "373 KB", "1,2 GB".
String bytesZin(int b) {
  String komma(double x, int d) => x.toStringAsFixed(d).replaceAll('.', ',');
  if (b >= 1 << 30) return '${komma(b / (1 << 30), 2)} GB';
  if (b >= 1 << 20) return '${komma(b / (1 << 20), b >= 100 << 20 ? 0 : 1)} MB';
  if (b >= 1 << 10) return '${(b / 1024).round()} KB';
  return '$b B';
}

/// De dag als sleutel: "2026-10-27".
String dagSleutel(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// Het netwerk als sleutel.
String netSleutel(Netsoort n) => switch (n) {
      Netsoort.mobiel => 'mobiel',
      Netsoort.wifi => 'wifi',
      Netsoort.onbekend => 'onbekend',
    };

/// Wie de bytes van een aanvraag bij de pc telt ([TellendeClient]); null tot main.dart hem zet (de pc zelf, een toets).
void Function(Uri adres, int bytes)? telVerkeer;

/// Wat een aanvraag kost bovenop zijn inhoud: de koppen heen en terug, en de versleuteling eromheen. Zo telt een 304 —
/// een catalogus die niet veranderde — ook, en niet als niets.
const int kKoppenBytes = 600;

/// Een [http.Client] die telt wat er binnenkomt ([telVerkeer]), voor alles wat met de pc praat (`clientVoor`,
/// lan/client.dart). Een ingepakt antwoord (de catalogus met gzip) telt op zijn ingepakte lengte: dat ging over de lijn.
class TellendeClient extends http.BaseClient {
  TellendeClient(this._binnen);
  final http.Client _binnen;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = await _binnen.send(request);
    final tel = telVerkeer;
    if (tel == null) return r;
    final gezegd = int.tryParse(r.headers['content-length'] ?? '');
    final ingepakt = (r.headers['content-encoding'] ?? '').contains('gzip');
    final heen = request.contentLength ?? 0;
    var n = 0;
    final stroom = r.stream.transform(StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (d, s) {
        n += d.length;
        s.add(d);
      },
      handleDone: (s) {
        tel(request.url, (ingepakt && gezegd != null ? gezegd : n) + heen + kKoppenBytes);
        s.close();
      },
    ));
    return http.StreamedResponse(stroom, r.statusCode,
        contentLength: r.contentLength,
        request: r.request,
        headers: r.headers,
        isRedirect: r.isRedirect,
        persistentConnection: r.persistentConnection,
        reasonPhrase: r.reasonPhrase);
  }

  @override
  void close() => _binnen.close();
}

/// Wat Android telt voor deze app, of null (geen Android, of het systeem zegt het niet).
typedef Androidverbruik = ({int mobiel, int wifi});

const _kanaal = MethodChannel('debridmusic/device');

/// Wat Android voor deze app telde tussen [vanaf] en [tot] (in emmers van ongeveer twee uur).
Future<Androidverbruik?> androidVerbruik(DateTime vanaf, DateTime tot) async {
  if (!Platform.isAndroid) return null;
  try {
    final m = await _kanaal.invokeMapMethod<String, Object?>(
        'verbruik', {'vanaf': vanaf.millisecondsSinceEpoch, 'tot': tot.millisecondsSinceEpoch});
    if (m == null) return null;
    return (mobiel: (m['mobiel'] as num?)?.toInt() ?? 0, wifi: (m['wifi'] as num?)?.toInt() ?? 0);
  } catch (_) {
    return null;
  }
}

/// Wat deze app sinds het opstarten van het toestel ontving plus verstuurde (alle netwerken), of null.
Future<int?> androidVerkeer() async {
  if (!Platform.isAndroid) return null;
  try {
    final m = await _kanaal.invokeMapMethod<String, Object?>('verkeer');
    final rx = (m?['rx'] as num?)?.toInt() ?? -1, tx = (m?['tx'] as num?)?.toInt() ?? -1;
    return rx < 0 || tx < 0 ? null : rx + tx;
  } catch (_) {
    return null;
  }
}

/// Eén dag: per netwerk, per soort, de bytes. "totaal" is wat Android over die tijd zag (alles van de app).
class Verbruiksdag {
  Verbruiksdag([Map<String, Map<String, int>>? per]) : per = per ?? {};
  final Map<String, Map<String, int>> per;

  int van(String net, String soort) => per[net]?[soort] ?? 0;
  void tel(String net, String soort, int bytes) {
    final m = per.putIfAbsent(net, () => {});
    m[soort] = (m[soort] ?? 0) + bytes;
  }

  /// Wat de app zelf telde op [net], alle soorten samen.
  int geteld(String net) => [for (final s in Verkeerssoort.values) van(net, s.name)].fold(0, (a, b) => a + b);

  Map<String, Object?> toJson() => per;
  static Verbruiksdag uitJson(Object? j) => Verbruiksdag({
        if (j is Map)
          for (final e in j.entries)
            if (e.value is Map)
              '${e.key}': {
                for (final f in (e.value as Map).entries)
                  if (f.value is num) '${f.key}': (f.value as num).toInt(),
              },
      });
}

/// Het dataverbruik van dit toestel: tellen, bewaren (`dataverbruik.json`, 92 dagen), en het logboek.
class DataverbruikStore extends ChangeNotifier {
  DataverbruikStore({required this.bestand, required this.logboek, required this.netNu, DateTime Function()? klok})
      : _klok = klok ?? DateTime.now;

  /// Waar de dagen bewaard worden; null = alleen in het geheugen (een toets).
  final String? bestand;

  /// Eén regel per gebeurtenis; null = geen logboek.
  final void Function(String regel)? logboek;

  /// Op welk netwerk het toestel nu zit.
  final Netsoort Function() netNu;
  final DateTime Function() _klok;

  final Map<String, Verbruiksdag> _dagen = {};
  Timer? _bewaren, _kwartier;
  bool _geladen = false;

  /// Regels voor de pc (`/api/diag/verbruik`): wie ze verstuurt, haalt ze op met [neemRegels].
  final List<String> _voorDePc = [];

  /// Wat er dit kwartier geteld is, per netwerk en soort — voor de samenvatting.
  final Verbruiksdag _ditKwartier = Verbruiksdag();
  int? _androidBijStart;

  /// Een grote haal (een nummer) krijgt een eigen regel vanaf deze grootte.
  static const int kEigenRegel = 1 << 20;

  Verbruiksdag dag(DateTime t) => _dagen[dagSleutel(t)] ?? Verbruiksdag();
  Iterable<String> get dagen => _dagen.keys;

  /// Een maand (de dagen van [t]'s maand tot en met vandaag) bij elkaar.
  Verbruiksdag maand(DateTime t) {
    final uit = Verbruiksdag();
    final voor = '${dagSleutel(t).substring(0, 7)}-';
    for (final e in _dagen.entries) {
      if (!e.key.startsWith(voor)) continue;
      for (final n in e.value.per.entries) {
        for (final s in n.value.entries) {
          uit.tel(n.key, s.key, s.value);
        }
      }
    }
    return uit;
  }

  Future<void> laad() async {
    if (_geladen) return;
    _geladen = true;
    final b = bestand;
    if (b != null) {
      try {
        final j = jsonDecode(await File(b).readAsString());
        if (j is Map) {
          for (final e in j.entries) {
            _dagen['${e.key}'] = Verbruiksdag.uitJson(e.value);
          }
        }
      } catch (_) {/* geen of een kapot bestand: opnieuw beginnen */}
    }
    _androidBijStart = await androidVerkeer();
    _kwartier ??= Timer.periodic(const Duration(minutes: 15), (_) => unawaited(kwartier()));
  }

  /// [bytes] van soort [soort] zijn over de lijn gegaan, nu, op het netwerk van nu. [wat]: wat het was ("Foreigner – I
  /// Want to Know What Love Is", "/api/catalog"), voor de eigen regel van een grote haal.
  void tel(Verkeerssoort soort, int bytes, {String? wat}) {
    if (bytes <= 0) return;
    final net = netSleutel(netNu());
    final nu = _klok();
    _dagen.putIfAbsent(dagSleutel(nu), Verbruiksdag.new).tel(net, soort.name, bytes);
    _ditKwartier.tel(net, soort.name, bytes);
    if (bytes >= kEigenRegel) _regel(nu, '$net  ${soort.name}  ${bytesZin(bytes)}${wat == null ? '' : '  $wat'}');
    _bewaarStraks();
    notifyListeners();
  }

  /// De samenvatting van het kwartier, met wat Android in die tijd voor de hele app zag (alle netwerken).
  Future<void> kwartier() async {
    final nu = _klok();
    final android = await androidVerkeer();
    final vorig = _androidBijStart;
    _androidBijStart = android;
    final delen = <String>[];
    for (final n in _ditKwartier.per.entries) {
      final soorten = [
        for (final s in Verkeerssoort.values)
          if ((n.value[s.name] ?? 0) > 0) '${s.name} ${bytesZin(n.value[s.name]!)}',
      ];
      if (soorten.isNotEmpty) delen.add('${n.key}: ${soorten.join(', ')}');
    }
    final systeem = android != null && vorig != null && android >= vorig ? android - vorig : null;
    // Wat Android zag maar de app niet telde: ook dat staat in de dag, onder het netwerk van nu.
    if (systeem != null) {
      final geteld = [for (final n in _ditKwartier.per.keys) _ditKwartier.geteld(n)].fold(0, (a, b) => a + b);
      final rest = systeem - geteld;
      if (rest > 0) {
        final net = netSleutel(netNu());
        _dagen.putIfAbsent(dagSleutel(nu), Verbruiksdag.new).tel(net, 'ongeteld', rest);
        _bewaarStraks();
      }
    }
    _ditKwartier.per.clear();
    if (delen.isEmpty && (systeem ?? 0) < (64 << 10)) return;
    _regel(nu, 'kwartier  ${delen.isEmpty ? 'niets geteld' : delen.join(' | ')}'
        '${systeem == null ? '' : '  · Android: ${bytesZin(systeem)} (alle netwerken)'}');
    notifyListeners();
  }

  void _regel(DateTime t, String tekst) {
    final r = '${dagSleutel(t).substring(8)}-${dagSleutel(t).substring(5, 7)} $tekst';
    logboek?.call(r);
    _voorDePc.add(r);
    if (_voorDePc.length > 200) _voorDePc.removeRange(0, _voorDePc.length - 200);
  }

  /// De regels die nog naar de pc moeten, en leeg daarna.
  List<String> neemRegels() {
    final r = List.of(_voorDePc);
    _voorDePc.clear();
    return r;
  }

  /// Niet verstuurd: terug vooraan.
  void legTerug(List<String> regels) => _voorDePc.insertAll(0, regels);

  void _bewaarStraks() {
    final b = bestand;
    if (b == null) return;
    _bewaren?.cancel();
    _bewaren = Timer(const Duration(seconds: 20), () async {
      // 92 dagen bewaren: drie maanden om te vergelijken.
      final grens = dagSleutel(_klok().subtract(const Duration(days: 92)));
      _dagen.removeWhere((k, _) => k.compareTo(grens) < 0);
      try {
        final tmp = File('$b.tmp');
        await tmp.writeAsString(jsonEncode({for (final e in _dagen.entries) e.key: e.value.toJson()}));
        await tmp.rename(b);
      } catch (_) {/* volgende keer */}
    });
  }

  @override
  void dispose() {
    _bewaren?.cancel();
    _kwartier?.cancel();
    super.dispose();
  }
}
