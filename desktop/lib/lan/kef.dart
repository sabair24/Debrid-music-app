/// De KEF LS50 Wireless II (en andere speakers op de StreamSDK van StreamUnlimited) via zijn eigen API op
/// poort 80, zoals KEF Connect hem bedient — niet via UPnP.
///
/// **Waarom.** Op 22-10-2026 antwoordde de KEF van Saber niet meer als UPnP-speaker (geen SSDP, geen
/// UPnP-poort open), terwijl hij via KEF Connect gewoon Tidal speelde en zich via mDNS aankondigde
/// (`_kef-info._tcp`, `_airplay._tcp`). Via de API speelt hij een adres van de pc op volle resolutie:
/// gemeten 24 bit / 96 kHz FLAC, ~3,07 Mbit/s, door de KEF zelf gedecodeerd ("activeResource").
///
/// **Wat de API doet (gemeten 22-10, firmware 4.1.192):**
/// - lezen: `GET /api/getData?path=…&roles=value`; zetten: `POST /api/setData` met `{path, role, value}`
///   (een GET daar geeft 405);
/// - spelen: `player:player/control` + `{control: play, mediaRoles: {type: audio, …, resources: [{uri}]}}`;
///   `play` zónder nummer is géén verder spelen (500 "Directory is empty", en hij stopt);
/// - `pause` is een aan/uit-knop: pauze, nog eens = verder. Dus eerst de stand lezen;
/// - spoelen: `{control: seekTime, time: <ms>}`; de plek: `player:player/data/playTime` in ms, ongeveer
///   elke 1008 ms bijgewerkt, in blokjes van 48 ms; `-1` vlak na de start;
/// - volume: `player:volume` (`i32_`); bron: `settings:/kef/play/physicalSource` (`wifi` = netwerk).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'net.dart';
import 'upnp.dart';

/// Een KEF als [Renderer]: herkenbaar aan dit voorvoegsel in [Renderer.avTransportUrl].
const kKefVoorvoegsel = 'kef://';

/// Een [Renderer] voor de KEF op [host].
Renderer kefRenderer({required String host, required String naam, String model = ''}) => Renderer(
      id: host,
      name: naam,
      host: host,
      avTransportUrl: '$kKefVoorvoegsel$host',
      manufacturer: 'KEF',
      model: model,
    );

/// Is [r] een KEF die via zijn API bediend wordt?
bool isKef(Renderer r) => r.avTransportUrl.startsWith(kKefVoorvoegsel);

/// Wat de KEF krijgt om [uri] te spelen (de waarde van `player:player/control`). Zuiver, voor toetsen.
Map<String, dynamic> kefSpeelOpdracht({
  required String uri,
  required String titel,
  required String artiest,
  required String album,
  required String mime,
  String? hoes,
  Duration? duur,
}) =>
    {
      'control': 'play',
      'mediaRoles': {
        'type': 'audio',
        'title': titel,
        'mimeType': mime,
        'mediaData': {
          'metaData': {
            'artist': artiest,
            'album': album,
            if (hoes != null && hoes.isNotEmpty) 'albumCoverUri': hoes,
          },
          'resources': [
            {
              'mimeType': mime,
              'uri': uri,
              if (duur != null && duur > Duration.zero) 'duration': duur.inMilliseconds,
            },
          ],
        },
      },
    };

/// De eerste waarde uit een `getData`-antwoord (een lijst met één item), of null.
Object? kefWaarde(String body) {
  try {
    final j = jsonDecode(body);
    if (j is List && j.isNotEmpty) return j.first;
  } catch (_) {}
  return null;
}

/// Het getal uit `[{"type":"i64_","i64_":22198}]` (of `i32_`), of null.
int? kefGetal(String body) {
  final w = kefWaarde(body);
  if (w is! Map) return null;
  final v = w['i64_'] ?? w['i32_'];
  return v is num ? v.toInt() : null;
}

/// De stand uit `player:player/data` ('playing', 'paused', 'stopped', …), de lengte (ms) en het adres
/// dat speelt.
({String stand, int duurMs, String? uri}) kefSpeler(String body) {
  final w = kefWaarde(body);
  if (w is! Map) return (stand: '', duurMs: 0, uri: null);
  final status = w['status'];
  final duur = status is Map ? status['duration'] : null;
  String? uri;
  final media = (w['trackRoles'] is Map) ? (w['trackRoles'] as Map)['mediaData'] : null;
  if (media is Map) {
    final bronnen = media['resources'];
    if (bronnen is List && bronnen.isNotEmpty && bronnen.first is Map) {
      final b = bronnen.first as Map;
      uri = '${b['uri'] ?? b['data'] ?? ''}';
      if (uri.isEmpty) uri = null;
    }
  }
  return (stand: '${w['state'] ?? ''}', duurMs: duur is num ? duur.toInt() : 0, uri: uri);
}

/// Een mDNS-vraag (PTR) naar [dienst], bv. `_kef-info._tcp.local`. Zuiver, voor toetsen.
Uint8List mdnsVraag(String dienst) {
  final b = BytesBuilder()..add(const [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
  for (final deel in dienst.split('.')) {
    final d = utf8.encode(deel);
    b
      ..addByte(d.length)
      ..add(d);
  }
  b.add(const [0, 0, 12, 0, 1]);
  return b.toBytes();
}

/// Zegt dit mDNS-antwoord iets over [dienst] (bv. `_kef-info`)? Grof maar genoeg: de naam staat er letterlijk
/// in. Antwoorden op de groep bevatten ook andermans records; de pc vraagt de API daarna toch na.
bool mdnsNoemt(List<int> pakket, String dienst) => latin1.decode(pakket, allowInvalid: true).contains(dienst);

/// Zoekt KEF's op het netwerk: een mDNS-vraag naar `_kef-info._tcp` op elke netwerkkaart, en per antwoord
/// de naam via de API. Echte IO: alleen in de app, niet in een toets.
Future<List<Renderer>> zoekKefs({Duration wacht = const Duration(seconds: 2)}) async {
  final adressen = <String>{};
  final sockets = <RawDatagramSocket>[];
  final groep = InternetAddress('224.0.0.251');
  final vraag = mdnsVraag('_kef-info._tcp.local');
  for (final eigen in await lanAddresses()) {
    try {
      final s = await RawDatagramSocket.bind(InternetAddress(eigen), 0);
      s.multicastHops = 1;
      s.listen((e) {
        if (e != RawSocketEvent.read) return;
        final p = s.receive();
        if (p != null && mdnsNoemt(p.data, '_kef-info')) adressen.add(p.address.address);
      });
      s.send(vraag, groep, 5353);
      sockets.add(s);
    } on SocketException catch (e) {
      debugPrint('mDNS: kan niet zoeken vanaf $eigen: ${e.message}');
    }
  }
  await Future<void>.delayed(wacht);
  for (final s in sockets) {
    s.close();
  }
  final uit = <Renderer>[];
  for (final host in adressen) {
    final api = KefApi(host);
    try {
      final naam = await api.naam();
      if (naam == null) continue;
      uit.add(kefRenderer(host: host, naam: naam, model: await api.model() ?? ''));
    } catch (_) {
      // Geen KEF-API achter dit adres.
    } finally {
      api.sluit();
    }
  }
  return uit;
}

/// De API van één KEF.
class KefApi {
  KefApi(this.host, {this.poort = 80}) : _client = HttpClient()..connectionTimeout = const Duration(seconds: 3);

  final String host;
  final int poort;
  final HttpClient _client;

  void sluit() => _client.close(force: true);

  Future<String> _lees(String pad) async {
    final url = Uri(scheme: 'http', host: host, port: poort, path: '/api/getData', queryParameters: {
      'path': pad,
      'roles': 'value',
    });
    final req = await _client.getUrl(url);
    final res = await req.close().timeout(const Duration(seconds: 5));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) throw HttpException('KEF $pad: HTTP ${res.statusCode}');
    return body;
  }

  Future<void> _zet(String pad, String rol, Object waarde) async {
    final req = await _client.postUrl(Uri(scheme: 'http', host: host, port: poort, path: '/api/setData'));
    final lijf = utf8.encode(jsonEncode({'path': pad, 'role': rol, 'value': waarde}));
    req.headers.contentType = ContentType.json;
    req.contentLength = lijf.length;
    req.add(lijf);
    final res = await req.close().timeout(const Duration(seconds: 8));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw HttpException('KEF weigerde $pad (HTTP ${res.statusCode}): ${body.substring(0, body.length.clamp(0, 200))}');
    }
  }

  Future<String?> naam() async {
    final w = kefWaarde(await _lees('settings:/deviceName'));
    return w is Map ? w['string_'] as String? : null;
  }

  Future<String?> model() async {
    final w = kefWaarde(await _lees('settings:/kef/host/modelName'));
    return w is Map ? w['string_'] as String? : null;
  }

  Future<({String stand, int duurMs, String? uri})> speler() async => kefSpeler(await _lees('player:player/data'));

  /// De plek in ms, of null (`-1` vlak na de start).
  Future<int?> plekMs() async {
    final v = kefGetal(await _lees('player:player/data/playTime'));
    return v == null || v < 0 ? null : v;
  }

  Future<void> speel(Map<String, dynamic> opdracht) async {
    // Op een andere bron (optisch, tv, Bluetooth) of in stand-by: eerst naar het netwerk.
    final bron = kefWaarde(await _lees('settings:/kef/play/physicalSource'));
    if (bron is Map && bron['kefPhysicalSource'] != 'wifi') {
      await _zet('settings:/kef/play/physicalSource', 'value',
          {'type': 'kefPhysicalSource', 'kefPhysicalSource': 'wifi'});
    }
    await _zet('player:player/control', 'activate', opdracht);
  }

  /// `pause` is een aan/uit-knop: alleen drukken als de stand het andere is.
  Future<void> pauzeer() async {
    if ((await speler()).stand == 'playing') await _zet('player:player/control', 'activate', {'control': 'pause'});
  }

  Future<void> verder() async {
    if ((await speler()).stand == 'paused') await _zet('player:player/control', 'activate', {'control': 'pause'});
  }

  Future<void> stop() => _zet('player:player/control', 'activate', {'control': 'stop'});

  Future<void> spoel(int ms) => _zet('player:player/control', 'activate', {'control': 'seekTime', 'time': ms});

  Future<int?> volume() async => kefGetal(await _lees('player:volume'));

  Future<void> zetVolume(int v) => _zet('player:volume', 'value', {'type': 'i32_', 'i32_': v.clamp(0, 100)});
}

/// Wat de cast met een KEF doet, in de vorm van [UpnpControlPoint] — zo hoeft de cast niet te weten of een
/// speaker UPnP of de KEF-API spreekt. Een volgend nummer klaarzetten (naadloos) kent de API niet; de cast
/// ziet het einde aan "stopped" en opent dan het volgende.
class KefBediening extends UpnpControlPoint {
  KefBediening({int poort = 80}) : _poort = poort;

  final int _poort;
  final Map<String, KefApi> _apis = {};

  KefApi _api(Renderer r) => _apis.putIfAbsent(r.host, () => KefApi(r.host, poort: _poort));

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
      _api(renderer).speel(kefSpeelOpdracht(
          uri: url, titel: title, artiest: artist, album: album, mime: mime, hoes: artUrl, duur: duration));

  @override
  Future<void> setNextUrl(Renderer renderer, String url,
      {required String title,
      required String artist,
      required String album,
      required String mime,
      String? artUrl,
      Duration? duration}) async {}

  @override
  Future<void> play(Renderer r) => _api(r).verder();

  @override
  Future<void> pause(Renderer r) => _api(r).pauzeer();

  @override
  Future<void> stop(Renderer r) => _api(r).stop();

  @override
  Future<void> seek(Renderer r, Duration to) => _api(r).spoel(to.inMilliseconds);

  @override
  Future<int?> getVolume(Renderer r) => _api(r).volume();

  @override
  Future<void> setVolume(Renderer r, int volume) => _api(r).zetVolume(volume);

  @override
  Future<({Duration? position, Duration duration, String? trackUri})?> positionInfo(Renderer r) async {
    final api = _api(r);
    final plek = await api.plekMs();
    final s = await api.speler();
    return (
      position: plek == null ? null : Duration(milliseconds: plek),
      duration: Duration(milliseconds: s.duurMs),
      trackUri: s.uri,
    );
  }

  @override
  Future<TransportState?> transportState(Renderer r) async {
    final s = (await _api(r).speler()).stand;
    return TransportState(switch (s) {
      'playing' => 'PLAYING',
      'paused' => 'PAUSED_PLAYBACK',
      'stopped' || '' => 'STOPPED',
      _ => 'TRANSITIONING',
    });
  }

  void sluit() {
    for (final a in _apis.values) {
      a.sluit();
    }
    _apis.clear();
  }
}
