/// Google Cast: de Nest Minis (en groepen uit Google Home) als speaker, naast Sonos (UPnP), de KEF (zijn API) en de
/// Shield (de eigen ontvanger).
///
/// **Waarom (Saber, 01-11-2026).** *"in huis ook nog 2 google mini nest die wil ik ook in de zones zien en alle functies
/// aan toevoegen wat de andere zones nu ook kunnen"*. Een Nest Mini spreekt geen UPnP: alleen Cast. Gekozen: groepen uit
/// Google Home als eigen zone, en kwaliteit het origineel tot 24/96 (daarboven zet de pc om, zie [Renderer.maxSampleRate]).
///
/// **Het protocol (CASTV2), gemeten op de Nest Mini "Kantoor" op 01-11-2026** (scratchpad/cast_proef.js):
/// - TLS naar poort 8009 (een eigen certificaat van het toestel, dat is gewoon zo bij Cast); elk bericht is 4 bytes lengte
///   plus een protobuf `CastMessage` met bron, doel, namespace en een JSON-tekst ([castBericht], [leesCastBericht]);
/// - `CONNECT` naar `receiver-0`, en elke 5 s een `PING` (anders sluit hij de verbinding);
/// - `LAUNCH` van de Default Media Receiver ([kStandaardOntvanger]): 2,9 s, en dan een `transportId` om de media naar te
///   sturen; `LOAD` met het adres van de pc: 0,3 s;
/// - `GET_STATUS` op de media geeft `currentTime` tot op de milliseconde, uitgerekend op het moment van de vraag
///   (gemeten +1,10 s per 1,1 s) — geen blokjes zoals de KEF, geen hele seconden zoals een Sonos;
/// - volume: `SET_VOLUME` op de ontvanger, `level` van 0 tot 1.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'kef.dart' show mdnsVraag;
import 'net.dart';
import 'upnp.dart';

/// Een Cast-speaker als [Renderer]: herkenbaar aan dit voorvoegsel in [Renderer.avTransportUrl] (`cast://host:poort`).
const kCastVoorvoegsel = 'cast://';

/// De Default Media Receiver: de speler van Google zelf, die een adres speelt.
const kStandaardOntvanger = 'CC1AD845';

const kCastVerbinding = 'urn:x-cast:com.google.cast.tp.connection';
const kCastHartslag = 'urn:x-cast:com.google.cast.tp.heartbeat';
const kCastOntvanger = 'urn:x-cast:com.google.cast.receiver';
const kCastMedia = 'urn:x-cast:com.google.cast.media';

/// Een [Renderer] voor de Cast-speaker [id] (de `id` uit zijn mDNS-aankondiging, vast ook als zijn adres verandert).
Renderer castRenderer({required String id, required String host, required int poort, required String naam, String model = ''}) =>
    Renderer(
      id: 'cast-$id',
      name: naam,
      host: host,
      avTransportUrl: '$kCastVoorvoegsel$host:$poort',
      manufacturer: 'Google',
      model: model,
    );

/// Wordt [r] via Google Cast bediend?
bool isCast(Renderer r) => r.avTransportUrl.startsWith(kCastVoorvoegsel);

/// Waar de Cast-speaker [r] luistert. Een groep uit Google Home woont op een van zijn leden, op een eigen poort.
({String host, int poort}) castAdres(Renderer r) {
  final rest = r.avTransportUrl.substring(kCastVoorvoegsel.length);
  final i = rest.lastIndexOf(':');
  return i < 0 ? (host: rest, poort: 8009) : (host: rest.substring(0, i), poort: int.tryParse(rest.substring(i + 1)) ?? 8009);
}

// ── Het bericht ───────────────────────────────────────────────────────────────────────────────────────────────────────

void _varint(BytesBuilder b, int n) {
  while (n > 127) {
    b.addByte((n & 127) | 128);
    n >>= 7;
  }
  b.addByte(n);
}

void _tekst(BytesBuilder b, int veld, String s) {
  final d = utf8.encode(s);
  _varint(b, (veld << 3) | 2);
  _varint(b, d.length);
  b.add(d);
}

/// Eén Cast-bericht, klaar om te sturen: 4 bytes lengte (big-endian) en de protobuf `CastMessage`
/// (protocol_version 0, source_id, destination_id, namespace, payload_type 0 = tekst, payload_utf8).
Uint8List castBericht({required String bron, required String doel, required String ns, required Map<String, dynamic> data}) {
  final lijf = BytesBuilder();
  _varint(lijf, (1 << 3) | 0);
  _varint(lijf, 0);
  _tekst(lijf, 2, bron);
  _tekst(lijf, 3, doel);
  _tekst(lijf, 4, ns);
  _varint(lijf, (5 << 3) | 0);
  _varint(lijf, 0);
  _tekst(lijf, 6, jsonEncode(data));
  final l = lijf.length;
  return Uint8List.fromList([(l >> 24) & 255, (l >> 16) & 255, (l >> 8) & 255, l & 255, ...lijf.takeBytes()]);
}

/// Het lijf van een Cast-bericht (zonder de 4 bytes lengte) gelezen, of null als het geen tekstbericht is.
({String bron, String doel, String ns, Map<String, dynamic>? data})? leesCastBericht(Uint8List lijf) {
  final velden = <int, Object>{};
  var o = 0;
  int vi() {
    var r = 0, s = 0, b = 0;
    do {
      if (o >= lijf.length) throw const FormatException('afgekapt');
      b = lijf[o++];
      r |= (b & 127) << s;
      s += 7;
    } while (b & 128 != 0);
    return r;
  }

  try {
    while (o < lijf.length) {
      final tag = vi();
      final veld = tag >> 3, soort = tag & 7;
      if (soort == 0) {
        velden[veld] = vi();
      } else if (soort == 2) {
        final l = vi();
        if (o + l > lijf.length) return null;
        velden[veld] = Uint8List.sublistView(lijf, o, o + l);
        o += l;
      } else {
        return null;
      }
    }
  } on FormatException {
    return null;
  }
  String tekst(int v) => velden[v] is Uint8List ? utf8.decode(velden[v] as Uint8List, allowMalformed: true) : '';
  Map<String, dynamic>? data;
  final p = tekst(6);
  if (p.isNotEmpty) {
    try {
      final j = jsonDecode(p);
      if (j is Map) data = j.cast<String, dynamic>();
    } catch (_) {}
  }
  return (bron: tekst(2), doel: tekst(3), ns: tekst(4), data: data);
}

// ── Vinden (mDNS) ─────────────────────────────────────────────────────────────────────────────────────────────────────

/// Eén aankondiging van `_googlecast._tcp`: naam (`fn`), vaste id, model (`md`), waar hij luistert, en zijn
/// mogelijkheden (`ca`, een bitmasker: 1 = beeld uit, 4 = geluid uit, 32 = een groep).
typedef CastAankondiging = ({String naam, String id, String model, String host, int poort, int ca});

/// Een speaker of een groep, geen televisie: zonder beeld-uitgang. Een Shield of een tv met Chromecast heeft er een (en
/// heeft zijn eigen weg: de ontvanger van deze app).
bool isAudioCast(CastAankondiging a) => (a.ca & 1) == 0;

/// De aankondigingen van Cast-toestellen uit de mDNS-antwoorden [pakketten], met per pakket het adres [van] waar het
/// vandaan kwam (de terugval als er geen A-record bij zat). Zuiver, voor toetsen.
List<CastAankondiging> leesCastAankondigingen(List<({Uint8List data, String van})> pakketten) {
  final ptr = <String>{};
  final srv = <String, ({int poort, String doel, String van})>{};
  final txt = <String, Map<String, String>>{};
  final a = <String, String>{};
  for (final p in pakketten) {
    for (final r in _leesRecords(p.data)) {
      switch (r.soort) {
        case 12 when r.naam.toLowerCase() == '_googlecast._tcp.local':
          ptr.add(r.tekst);
        case 33:
          srv[r.naam] = (poort: r.poort, doel: r.tekst, van: p.van);
        case 16:
          txt[r.naam] = r.paren;
        case 1:
          a[r.naam.toLowerCase()] = r.tekst;
      }
    }
  }
  final uit = <CastAankondiging>[];
  for (final inst in {...ptr, ...srv.keys.where((k) => k.toLowerCase().endsWith('._googlecast._tcp.local'))}) {
    final s = srv[inst], t = txt[inst];
    if (s == null || t == null) continue;
    final id = t['id'] ?? '';
    if (id.isEmpty) continue;
    uit.add((
      naam: t['fn'] ?? inst.split('.').first,
      id: id,
      model: t['md'] ?? '',
      host: a[s.doel.toLowerCase()] ?? s.van,
      poort: s.poort,
      ca: int.tryParse(t['ca'] ?? '') ?? 0,
    ));
  }
  return uit;
}

typedef _Record = ({String naam, int soort, String tekst, int poort, Map<String, String> paren});

List<_Record> _leesRecords(Uint8List d) {
  final uit = <_Record>[];
  if (d.length < 12) return uit;
  int u16(int o) => (d[o] << 8) | d[o + 1];
  String naamOp(int o, [int diepte = 0]) {
    final delen = <String>[];
    while (o < d.length && diepte < 20) {
      final l = d[o];
      if (l == 0) break;
      if (l & 0xC0 == 0xC0) {
        if (o + 1 >= d.length) break;
        delen.add(naamOp(((l & 0x3F) << 8) | d[o + 1], diepte + 1));
        break;
      }
      if (o + 1 + l > d.length) break;
      delen.add(utf8.decode(d.sublist(o + 1, o + 1 + l), allowMalformed: true));
      o += 1 + l;
    }
    return delen.where((x) => x.isNotEmpty).join('.');
  }

  int naNaam(int o) {
    while (o < d.length) {
      final l = d[o];
      if (l == 0) return o + 1;
      if (l & 0xC0 == 0xC0) return o + 2;
      o += 1 + l;
    }
    return o;
  }

  try {
    final vragen = u16(4), records = u16(6) + u16(8) + u16(10);
    var o = 12;
    for (var i = 0; i < vragen; i++) {
      o = naNaam(o) + 4;
    }
    for (var i = 0; i < records && o + 10 <= d.length; i++) {
      final naam = naamOp(o);
      o = naNaam(o);
      final soort = u16(o), lengte = u16(o + 8);
      final data = o + 10;
      o = data + lengte;
      if (o > d.length) break;
      switch (soort) {
        case 12:
          uit.add((naam: naam, soort: 12, tekst: naamOp(data), poort: 0, paren: const {}));
        case 33:
          uit.add((naam: naam, soort: 33, tekst: naamOp(data + 6), poort: u16(data + 4), paren: const {}));
        case 16:
          final paren = <String, String>{};
          var q = data;
          while (q < data + lengte) {
            final l = d[q];
            final s = utf8.decode(d.sublist(q + 1, (q + 1 + l).clamp(0, data + lengte)), allowMalformed: true);
            final is_ = s.indexOf('=');
            if (is_ > 0) paren[s.substring(0, is_)] = s.substring(is_ + 1);
            q += 1 + l;
          }
          uit.add((naam: naam, soort: 16, tekst: '', poort: 0, paren: paren));
        case 1 when lengte == 4:
          uit.add((naam: naam, soort: 1, tekst: '${d[data]}.${d[data + 1]}.${d[data + 2]}.${d[data + 3]}', poort: 0, paren: const {}));
      }
    }
  } catch (_) {/* een kapot pakket: wat er al gelezen is, telt */}
  return uit;
}

/// Zoekt Cast-speakers en -groepen op het netwerk: een mDNS-vraag naar `_googlecast._tcp` op elke netwerkkaart. Alleen
/// wat geen beeld heeft ([isAudioCast]). Echte IO: alleen in de app, niet in een toets.
Future<List<Renderer>> zoekCasts({Duration wacht = const Duration(seconds: 2)}) async {
  final pakketten = <({Uint8List data, String van})>[];
  final sockets = <RawDatagramSocket>[];
  final groep = InternetAddress('224.0.0.251');
  final vraag = mdnsVraag('_googlecast._tcp.local');
  for (final eigen in await lanAddresses()) {
    try {
      final s = await RawDatagramSocket.bind(InternetAddress(eigen), 0);
      s.multicastHops = 1;
      s.listen((e) {
        if (e != RawSocketEvent.read) return;
        final p = s.receive();
        if (p != null) pakketten.add((data: p.data, van: p.address.address));
      });
      s.send(vraag, groep, 5353);
      sockets.add(s);
    } on SocketException catch (e) {
      debugPrint('mDNS (Cast): kan niet zoeken vanaf $eigen: ${e.message}');
    }
  }
  await Future<void>.delayed(wacht);
  for (final s in sockets) {
    s.close();
  }
  final gezien = <String>{};
  return [
    for (final a in leesCastAankondigingen(pakketten))
      if (isAudioCast(a) && gezien.add(a.id)) castRenderer(id: a.id, host: a.host, poort: a.poort, naam: a.naam, model: a.model),
  ];
}

// ── Eén verbinding ────────────────────────────────────────────────────────────────────────────────────────────────────

/// De verbinding met één Cast-speaker: TLS, het hartje, en vraag-en-antwoord op `requestId`. Blijft open zolang de app
/// hem gebruikt; valt hij weg, dan bij de volgende vraag een nieuwe.
class CastKanaal {
  CastKanaal(this.host, this.poort, {this.log, this.verbind});

  final String host;
  final int poort;
  final void Function(String)? log;

  /// Voor een toets: hoe de verbinding gemaakt wordt.
  final Future<SecureSocket> Function()? verbind;

  SecureSocket? _s;
  Future<void>? _bezig;
  final _buf = BytesBuilder(copy: false);
  int _id = 1;
  final Map<int, Completer<Map<String, dynamic>?>> _wacht = {};
  Timer? _hart;

  /// De Default Media Receiver zoals die nu draait: zijn transport (waar de media heen gaat) en sessie. Null: niet (meer).
  String? _transport, _sessie;

  /// Het transport van onze speler volgens de LAATSTE melding van de ontvanger (null: daar draaide hij niet). Een melding
  /// "weg" kan binnenkomen vlak na het antwoord op LAUNCH, nog vóór [zorgVoorSpeler] het transport onthield.
  String? _laatsteApp;

  /// Het laatste `MEDIA_STATUS` en zijn mediasessie.
  Map<String, dynamic>? laatsteMedia;
  int? get mediaSessie => (laatsteMedia?['mediaSessionId'] as num?)?.toInt();

  Future<void> _zorgVoorVerbinding() async {
    if (_s != null) return;
    final b = _bezig;
    if (b != null) return b;
    final klaar = Completer<void>();
    _bezig = klaar.future;
    try {
      final s = await (verbind?.call() ??
          SecureSocket.connect(host, poort, onBadCertificate: (_) => true, timeout: const Duration(seconds: 5)));
      _s = s;
      s.listen(_binnen, onError: (Object e) => _weg('fout: $e'), onDone: () => _weg('dicht'), cancelOnError: true);
      _stuur('receiver-0', kCastVerbinding, {'type': 'CONNECT'});
      _hart = Timer.periodic(const Duration(seconds: 5), (_) => _stuur('receiver-0', kCastHartslag, {'type': 'PING'}));
      klaar.complete();
    } catch (e) {
      klaar.completeError(e);
      rethrow;
    } finally {
      _bezig = null;
    }
  }

  void _weg(String waarom) {
    log?.call('cast $host: verbinding $waarom');
    _hart?.cancel();
    _hart = null;
    _s = null;
    _transport = null;
    _sessie = null;
    for (final w in _wacht.values) {
      if (!w.isCompleted) w.complete(null);
    }
    _wacht.clear();
  }

  void _stuur(String doel, String ns, Map<String, dynamic> data) {
    try {
      _s?.add(castBericht(bron: 'sender-0', doel: doel, ns: ns, data: data));
    } catch (_) {}
  }

  void _binnen(Uint8List data) {
    _buf.add(data);
    var alles = _buf.takeBytes();
    var o = 0;
    while (alles.length - o >= 4) {
      final l = (alles[o] << 24) | (alles[o + 1] << 16) | (alles[o + 2] << 8) | alles[o + 3];
      if (alles.length - o - 4 < l) break;
      final m = leesCastBericht(Uint8List.sublistView(alles, o + 4, o + 4 + l));
      o += 4 + l;
      if (m != null) _verwerk(m);
    }
    if (o < alles.length) _buf.add(Uint8List.sublistView(alles, o));
    alles = Uint8List(0);
  }

  void _verwerk(({String bron, String doel, String ns, Map<String, dynamic>? data}) m) {
    final d = m.data;
    if (d == null) return;
    final type = '${d['type'] ?? ''}';
    if (m.ns == kCastHartslag && type == 'PING') {
      _stuur(m.bron, kCastHartslag, {'type': 'PONG'});
      return;
    }
    if (type == 'MEDIA_STATUS') {
      final st = d['status'];
      if (st is List && st.isNotEmpty && st.first is Map) laatsteMedia = (st.first as Map).cast<String, dynamic>();
    }
    if (type == 'RECEIVER_STATUS') {
      // Draait onze speler niet meer (iemand anders castte iets), dan bij de volgende opdracht opnieuw starten.
      final apps = (d['status'] is Map ? (d['status'] as Map)['applications'] : null) as List?;
      final draait = apps?.whereType<Map>().where((a) => a['appId'] == kStandaardOntvanger).firstOrNull;
      _laatsteApp = draait?['transportId'] as String?;
      if (draait == null) {
        _transport = null;
        _sessie = null;
      }
    }
    if (m.ns == kCastVerbinding && type == 'CLOSE' && m.bron == _transport) {
      _transport = null;
      _sessie = null;
    }
    final r = (d['requestId'] as num?)?.toInt();
    final w = r == null ? null : _wacht.remove(r);
    if (w != null && !w.isCompleted) w.complete(d);
  }

  /// Stuur [data] naar [doel] in [ns] en wacht op het antwoord met hetzelfde `requestId` (of null na [wacht]).
  Future<Map<String, dynamic>?> vraag(String doel, String ns, Map<String, dynamic> data,
      {Duration wacht = const Duration(seconds: 8)}) async {
    await _zorgVoorVerbinding();
    final r = _id++;
    final c = Completer<Map<String, dynamic>?>();
    _wacht[r] = c;
    _stuur(doel, ns, {...data, 'requestId': r});
    return c.future.timeout(wacht, onTimeout: () {
      _wacht.remove(r);
      return null;
    });
  }

  /// De Default Media Receiver draaiend, en verbonden met zijn transport. Geeft het transport.
  Future<String> zorgVoorSpeler() async {
    await _zorgVoorVerbinding();
    final t = _transport;
    if (t != null) return t;
    var st = await vraag('receiver-0', kCastOntvanger, {'type': 'GET_STATUS'});
    Map? app(Map<String, dynamic>? s) => ((s?['status'] as Map?)?['applications'] as List?)
        ?.whereType<Map>()
        .where((a) => a['appId'] == kStandaardOntvanger)
        .firstOrNull;
    var a = app(st);
    if (a == null) {
      final klok = Stopwatch()..start();
      st = await vraag('receiver-0', kCastOntvanger, {'type': 'LAUNCH', 'appId': kStandaardOntvanger},
          wacht: const Duration(seconds: 15));
      a = app(st);
      log?.call('cast $host: speler gestart in ${klok.elapsedMilliseconds} ms');
    }
    final nieuw = a?['transportId'] as String?;
    if (nieuw == null) throw StateError('de Cast-speler op $host startte niet');
    _stuur(nieuw, kCastVerbinding, {'type': 'CONNECT'});
    // Zei de ontvanger intussen al dat hij weg is, dan niet onthouden: de volgende opdracht start hem opnieuw.
    if (_laatsteApp == nieuw) {
      _transport = nieuw;
      _sessie = a?['sessionId'] as String?;
    }
    return nieuw;
  }

  /// Speel [url].
  Future<void> laad(String url, {required String mime, required Map<String, dynamic> metadata, double vanaf = 0}) async {
    final t = await zorgVoorSpeler();
    final a = await vraag(t, kCastMedia, {
      'type': 'LOAD',
      'autoplay': true,
      'currentTime': vanaf,
      'media': {'contentId': url, 'contentType': mime, 'streamType': 'BUFFERED', 'metadata': metadata},
    }, wacht: const Duration(seconds: 15));
    if (a == null || a['type'] == 'LOAD_FAILED' || a['type'] == 'LOAD_CANCELLED' || a['type'] == 'INVALID_REQUEST') {
      throw StateError('de Cast-speler op $host nam het nummer niet aan (${a?['type'] ?? 'geen antwoord'})');
    }
  }

  /// Een mediaopdracht (`PLAY`, `PAUSE`, `STOP`, `SEEK`) voor wat er nu speelt. Niets als er niets speelt.
  Future<void> media(String type, [Map<String, dynamic> extra = const {}]) async {
    final t = _transport, ms = mediaSessie;
    if (t == null || ms == null) return;
    await vraag(t, kCastMedia, {'type': type, 'mediaSessionId': ms, ...extra});
  }

  /// Hoe het nummer er nu bij staat (`playerState`, `currentTime`, `media`), vers gevraagd. Null: er speelt niets van ons.
  Future<Map<String, dynamic>?> mediaStand() async {
    if (_transport == null) {
      // Na een herstart van de pc: draait onze speler nog op de speaker, dan meedoen in plaats van niets te weten.
      final st = await vraag('receiver-0', kCastOntvanger, {'type': 'GET_STATUS'});
      final apps = ((st?['status'] as Map?)?['applications'] as List?)?.whereType<Map>();
      if (apps?.any((a) => a['appId'] == kStandaardOntvanger) != true) return null;
      await zorgVoorSpeler();
    }
    final t = _transport;
    if (t == null) return null;
    final a = await vraag(t, kCastMedia, {'type': 'GET_STATUS'});
    final st = a?['status'];
    if (st is List && st.isNotEmpty && st.first is Map) {
      laatsteMedia = (st.first as Map).cast<String, dynamic>();
      return laatsteMedia;
    }
    if (st is List && st.isEmpty) laatsteMedia = null;
    return laatsteMedia;
  }

  /// Het volume van de speaker (0–100), of null.
  Future<int?> volume() async {
    final st = await vraag('receiver-0', kCastOntvanger, {'type': 'GET_STATUS'});
    final l = (((st?['status'] as Map?)?['volume'] as Map?)?['level'] as num?)?.toDouble();
    return l == null ? null : (l * 100).round();
  }

  Future<void> zetVolume(int volume) =>
      vraag('receiver-0', kCastOntvanger, {'type': 'SET_VOLUME', 'volume': {'level': (volume.clamp(0, 100)) / 100}});

  /// De speler van Google afsluiten (na "Stop"): de Nest is daarna vrij voor wie hem wil.
  Future<void> stopSpeler() async {
    final s = _sessie;
    if (s == null) return;
    await vraag('receiver-0', kCastOntvanger, {'type': 'STOP', 'sessionId': s});
    _transport = null;
    _sessie = null;
    laatsteMedia = null;
  }

  void sluit() {
    _hart?.cancel();
    try {
      _s?.destroy();
    } catch (_) {}
    _weg('gesloten');
  }
}

// ── Voor de cast ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// Wat de cast met een Cast-speaker doet, in de vorm van [UpnpControlPoint] — zoals [KefBediening]: de cast hoeft niet
/// te weten welke taal een speaker spreekt. Een volgend nummer klaarzetten kent deze eerste versie niet; de cast ziet het
/// einde aan "stopped" (de speler valt op IDLE met `FINISHED`) en opent dan het volgende.
class CastBediening extends UpnpControlPoint {
  CastBediening({this.log, this.verbind});

  final void Function(String)? log;

  /// Voor een toets: hoe een verbinding met [host]:[poort] gemaakt wordt.
  final Future<SecureSocket> Function(String host, int poort)? verbind;

  final Map<String, CastKanaal> _kanalen = {};

  CastKanaal kanaal(Renderer r) {
    final a = castAdres(r);
    final v = verbind;
    return _kanalen.putIfAbsent('${a.host}:${a.poort}',
        () => CastKanaal(a.host, a.poort, log: log, verbind: v == null ? null : () => v(a.host, a.poort)));
  }

  @override
  Future<List<Renderer>> discover({Duration timeout = const Duration(seconds: 3)}) async => const [];

  @override
  Future<void> playUrl(Renderer renderer, String url,
          {required String title,
          required String artist,
          required String album,
          required String mime,
          String? artUrl,
          Duration? duration}) =>
      kanaal(renderer).laad(url, mime: mime, metadata: {
        // 3 = een muzieknummer: dan toont Google Home titel, artiest en plaat.
        'metadataType': 3,
        'title': title,
        'artist': artist,
        'albumName': album,
        if (artUrl != null && artUrl.isNotEmpty)
          'images': [
            {'url': artUrl}
          ],
      });

  @override
  Future<void> setNextUrl(Renderer renderer, String url,
      {required String title,
      required String artist,
      required String album,
      required String mime,
      String? artUrl,
      Duration? duration}) async {}

  @override
  Future<void> play(Renderer r) => kanaal(r).media('PLAY');

  @override
  Future<void> pause(Renderer r) => kanaal(r).media('PAUSE');

  @override
  Future<void> stop(Renderer r) => kanaal(r).media('STOP');

  @override
  Future<void> seek(Renderer r, Duration to) => kanaal(r).media('SEEK', {'currentTime': to.inMilliseconds / 1000});

  @override
  Future<int?> getVolume(Renderer r) => kanaal(r).volume();

  @override
  Future<void> setVolume(Renderer r, int volume) => kanaal(r).zetVolume(volume);

  @override
  Future<({Duration? position, Duration duration, String? trackUri})?> positionInfo(Renderer r) async {
    final m = await kanaal(r).mediaStand();
    if (m == null) return null;
    final t = (m['currentTime'] as num?)?.toDouble();
    final media = m['media'] as Map?;
    final duur = (media?['duration'] as num?)?.toDouble();
    return (
      position: t == null ? null : Duration(milliseconds: (t * 1000).round()),
      duration: duur == null ? Duration.zero : Duration(milliseconds: (duur * 1000).round()),
      trackUri: media?['contentId'] as String?,
    );
  }

  @override
  Future<TransportState?> transportState(Renderer r) async {
    final m = await kanaal(r).mediaStand();
    return TransportState(castStand(m?['playerState'] as String?));
  }

  void sluit() {
    for (final k in _kanalen.values) {
      k.sluit();
    }
    _kanalen.clear();
  }
}

/// De stand van een Cast-speler in de woorden van UPnP. IDLE (ook na het einde, `idleReason: FINISHED`) is "stopped":
/// daaraan ziet de cast dat het nummer op is.
String castStand(String? playerState) => switch (playerState) {
      'PLAYING' => 'PLAYING',
      'PAUSED' => 'PAUSED_PLAYBACK',
      'BUFFERING' || 'LOADING' => 'TRANSITIONING',
      _ => 'STOPPED',
    };
