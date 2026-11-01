/// Google Cast: de Nest Minis als speaker (Saber, 01-11-2026). Het protocol is op de echte Nest Mini "Kantoor" nagemeten
/// (scratchpad/cast_proef.js); hier tegen een nep-Nest over een echte TLS-verbinding, die doet wat de echte deed:
/// CONNECT, PING/PONG, GET_STATUS, LAUNCH (transportId), LOAD, MEDIA_STATUS met currentTime, SET_VOLUME.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/google_cast.dart';
import 'package:debridmusic/lan/upnp.dart';

import 'hulp_tls.dart';

/// Een nep-Nest: één Default Media Receiver, wat hij binnenkreeg in [binnen].
class _NepNest {
  late SecureServerSocket server;
  final binnen = <Map<String, dynamic>>[];
  final klanten = <SecureSocket>[];
  bool speelt = false, appDraait = false;
  int lanceringen = 0;
  double volume = .4, tijd = 0;
  String? contentId;
  /// Na een LAUNCH zegt hij (zoals wanneer iemand anders iets castte) dat onze speler niet meer draait.
  bool vergeetApp = false;

  int get poort => server.port;

  Future<void> start() async {
    server = await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, proefCertificaat.context());
    server.listen((s) {
      klanten.add(s);
      final buf = BytesBuilder(copy: false);
      s.listen((d) {
        buf.add(d);
        var alles = buf.takeBytes();
        var o = 0;
        while (alles.length - o >= 4) {
          final l = (alles[o] << 24) | (alles[o + 1] << 16) | (alles[o + 2] << 8) | alles[o + 3];
          if (alles.length - o - 4 < l) break;
          final m = leesCastBericht(Uint8List.sublistView(alles, o + 4, o + 4 + l))!;
          o += 4 + l;
          _verwerk(s, m);
        }
        if (o < alles.length) buf.add(Uint8List.sublistView(alles, o));
        alles = Uint8List(0);
      }, onError: (_) {});
    });
  }

  void _stuur(SecureSocket s, String bron, String ns, Map<String, dynamic> data) =>
      s.add(castBericht(bron: bron, doel: 'sender-0', ns: ns, data: data));

  Map<String, dynamic> _ontvanger(int? r) => {
        'type': 'RECEIVER_STATUS',
        'requestId': ?r,
        'status': {
          'volume': {'level': volume},
          'applications': [
            if (appDraait) {'appId': kStandaardOntvanger, 'transportId': 'web-7', 'sessionId': 'sessie-7'}
          ],
        },
      };

  void _verwerk(SecureSocket s, ({String bron, String doel, String ns, Map<String, dynamic>? data}) m) {
    final d = m.data!;
    binnen.add({...d, '_doel': m.doel, '_ns': m.ns});
    final r = (d['requestId'] as num?)?.toInt();
    switch (d['type']) {
      case 'PING':
        _stuur(s, m.doel, kCastHartslag, {'type': 'PONG'});
      case 'GET_STATUS' when m.ns == kCastOntvanger:
        _stuur(s, 'receiver-0', kCastOntvanger, _ontvanger(r));
      case 'LAUNCH':
        lanceringen++;
        appDraait = true;
        _stuur(s, 'receiver-0', kCastOntvanger, _ontvanger(r));
        if (vergeetApp) {
          appDraait = false;
          vergeetApp = false;
          _stuur(s, 'receiver-0', kCastOntvanger, _ontvanger(null));
        }
      case 'SET_VOLUME':
        volume = ((d['volume'] as Map)['level'] as num).toDouble();
        _stuur(s, 'receiver-0', kCastOntvanger, _ontvanger(r));
      case 'LOAD':
        contentId = (d['media'] as Map)['contentId'] as String;
        speelt = true;
        tijd = (d['currentTime'] as num?)?.toDouble() ?? 0;
        _stuur(s, m.doel, kCastMedia, _media(r));
      case 'GET_STATUS' when m.ns == kCastMedia:
        _stuur(s, m.doel, kCastMedia, _media(r));
      case 'PAUSE':
        speelt = false;
        _stuur(s, m.doel, kCastMedia, _media(r));
      case 'PLAY':
        speelt = true;
        _stuur(s, m.doel, kCastMedia, _media(r));
      case 'SEEK':
        tijd = (d['currentTime'] as num).toDouble();
        _stuur(s, m.doel, kCastMedia, _media(r));
      case 'STOP':
        speelt = false;
        _stuur(s, m.doel, m.ns, m.ns == kCastMedia ? _media(r) : _ontvanger(r));
    }
  }

  Map<String, dynamic> _media(int? r) => {
        'type': 'MEDIA_STATUS',
        'requestId': ?r,
        'status': [
          if (contentId != null)
            {
              'mediaSessionId': 1,
              'playerState': speelt ? 'PLAYING' : 'PAUSED',
              'currentTime': tijd,
              'media': {'contentId': contentId, 'duration': 245.5},
            }
        ],
      };

  /// Iemand anders castte iets op deze Nest: onze speler is weg, en de Nest zegt het tegen iedereen.
  void andereCast() {
    appDraait = false;
    for (final k in klanten) {
      _stuur(k, 'receiver-0', kCastOntvanger, _ontvanger(null));
    }
  }

  Future<void> stop() async {
    for (final k in klanten) {
      k.destroy();
    }
    await server.close();
  }
}

void main() {
  group('het bericht', () {
    test('heen en terug, met de lengte ervoor', () {
      final b = castBericht(bron: 'sender-0', doel: 'receiver-0', ns: kCastOntvanger, data: {'type': 'GET_STATUS', 'requestId': 3});
      final l = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
      expect(l, b.length - 4);
      final m = leesCastBericht(Uint8List.sublistView(b, 4))!;
      expect(m.bron, 'sender-0');
      expect(m.doel, 'receiver-0');
      expect(m.ns, kCastOntvanger);
      expect(m.data, {'type': 'GET_STATUS', 'requestId': 3});
    });

    test('een afgekapt of vreemd bericht geeft niets, en geen fout', () {
      final b = castBericht(bron: 'a', doel: 'b', ns: 'c', data: {'x': 'é'});
      expect(leesCastBericht(Uint8List.sublistView(b, 4, b.length - 3)), isNull);
      expect(leesCastBericht(Uint8List.fromList([0x0f])), isNull);
    });
  });

  group('vinden', () {
    /// Een mDNS-antwoord zoals een Nest het geeft: PTR, SRV, TXT en A, met naamcompressie.
    Uint8List antwoord({required String inst, required String fn, required String id, required int ca, required int poort,
        required List<int> ip, String md = 'Google Nest Mini'}) {
      final b = BytesBuilder();
      void naam(String n) {
        for (final deel in n.split('.')) {
          final d = utf8.encode(deel);
          b
            ..addByte(d.length)
            ..add(d);
        }
        b.addByte(0);
      }

      void u16(int v) => b.add([v >> 8, v & 255]);
      void u32(int v) => b.add([v >> 24, (v >> 16) & 255, (v >> 8) & 255, v & 255]);
      b.add([0, 0, 0x84, 0, 0, 0, 0, 4, 0, 0, 0, 0]);
      // PTR: _googlecast._tcp.local → inst (de naam van de dienst staat op plek 12; later naar verwezen).
      naam('_googlecast._tcp.local');
      u16(12);
      u16(1);
      u32(120);
      final instNaam = BytesBuilder();
      final d0 = utf8.encode(inst);
      instNaam
        ..addByte(d0.length)
        ..add(d0)
        ..add([0xC0, 12]);
      u16(instNaam.length);
      b.add(instNaam.toBytes());
      // SRV voor de instantie (volledig uitgeschreven), doel = host.local.
      naam('$inst._googlecast._tcp.local');
      u16(33);
      u16(0x8001);
      u32(120);
      final doel = BytesBuilder();
      for (final deel in ['nest-$id', 'local']) {
        final d = utf8.encode(deel);
        doel
          ..addByte(d.length)
          ..add(d);
      }
      doel.addByte(0);
      u16(6 + doel.length);
      u16(0);
      u16(0);
      u16(poort);
      b.add(doel.toBytes());
      // TXT
      naam('$inst._googlecast._tcp.local');
      u16(16);
      u16(0x8001);
      u32(120);
      final txt = BytesBuilder();
      for (final p in ['id=$id', 'md=$md', 'fn=$fn', 'ca=$ca']) {
        final d = utf8.encode(p);
        txt
          ..addByte(d.length)
          ..add(d);
      }
      u16(txt.length);
      b.add(txt.toBytes());
      // A
      naam('nest-$id.local');
      u16(1);
      u16(0x8001);
      u32(120);
      u16(4);
      b.add(ip);
      return b.toBytes();
    }

    test('een Nest Mini en een groep uit Google Home; de Shield (beeld) niet', () {
      final pakketten = [
        (data: antwoord(inst: 'Google-Nest-Mini-a1', fn: 'Kantoor', id: 'a1', ca: 199172, poort: 8009, ip: [192, 168, 0, 253]), van: '192.168.0.253'),
        (data: antwoord(inst: 'Google-Cast-Group-g9', fn: 'Beneden', id: 'g9', ca: 199204, poort: 32187, ip: [192, 168, 0, 184], md: 'Google Cast Group'), van: '192.168.0.184'),
        (data: antwoord(inst: 'SHIELD-Android-TV-s1', fn: 'Tv in woonkamer', id: 's1', ca: 463365, poort: 8009, ip: [192, 168, 0, 238], md: 'SHIELD Android TV'), van: '192.168.0.238'),
      ];
      final alles = leesCastAankondigingen(pakketten);
      expect({for (final a in alles) a.naam}, {'Kantoor', 'Beneden', 'Tv in woonkamer'});
      final kantoor = alles.firstWhere((a) => a.naam == 'Kantoor');
      expect(kantoor.host, '192.168.0.253');
      expect(kantoor.poort, 8009);
      expect(kantoor.model, 'Google Nest Mini');
      final groep = alles.firstWhere((a) => a.naam == 'Beneden');
      expect((groep.host, groep.poort), ('192.168.0.184', 32187), reason: 'een groep woont op een lid, op een eigen poort');
      expect([for (final a in alles) if (isAudioCast(a)) a.naam], ['Kantoor', 'Beneden'], reason: 'geen televisie');
    });

    test('een Cast-renderer: herkenbaar, met zijn adres en het plafond 24/96', () {
      final r = castRenderer(id: 'a1', host: '192.168.0.253', poort: 8009, naam: 'Kantoor', model: 'Google Nest Mini');
      expect(isCast(r), isTrue);
      expect(castAdres(r), (host: '192.168.0.253', poort: 8009));
      expect(r.maxSampleRate, 96000);
      expect(r.maxBitDepth, 24);
      expect(r.toJson()['kind'], 'cast');
      expect(r.id, 'cast-a1');
      final g = castRenderer(id: 'g9', host: '192.168.0.184', poort: 32187, naam: 'Beneden');
      expect(castAdres(g), (host: '192.168.0.184', poort: 32187));
    });
  });

  group('bedienen (tegen een nep-Nest)', () {
    late _NepNest nest;
    late CastBediening cast;
    late Renderer r;

    setUp(() async {
      nest = _NepNest();
      await nest.start();
      cast = CastBediening(verbind: (h, p) => pinSocket(p));
      r = castRenderer(id: 'a1', host: '127.0.0.1', poort: nest.poort, naam: 'Kantoor');
    });

    tearDown(() async {
      cast.sluit();
      await nest.stop();
    });

    test('DE KERN: spelen start de speler van Google één keer, laadt het adres, en de stand komt terug', () async {
      await cast.playUrl(r, 'http://pc/stream/1.flac?maxRate=96000', title: 'Bad', artist: 'Michael Jackson', album: 'Bad', mime: 'audio/flac');
      expect(nest.lanceringen, 1);
      final load = nest.binnen.firstWhere((m) => m['type'] == 'LOAD');
      expect(load['_doel'], 'web-7', reason: 'naar het transport van de speler, niet naar receiver-0');
      expect((load['media'] as Map)['contentId'], 'http://pc/stream/1.flac?maxRate=96000');
      expect(((load['media'] as Map)['metadata'] as Map)['title'], 'Bad');
      expect(nest.binnen.where((m) => m['type'] == 'CONNECT' && m['_doel'] == 'web-7'), hasLength(1));

      nest.tijd = 12.345;
      final p = await cast.positionInfo(r);
      expect(p!.position, const Duration(milliseconds: 12345));
      expect(p.duration, const Duration(milliseconds: 245500));
      expect(p.trackUri, 'http://pc/stream/1.flac?maxRate=96000');
      expect((await cast.transportState(r))!.state, 'PLAYING');

      await cast.playUrl(r, 'http://pc/stream/2.flac', title: 'Speed Demon', artist: 'Michael Jackson', album: 'Bad', mime: 'audio/flac');
      expect(nest.lanceringen, 1, reason: 'het volgende nummer: de speler draait al');
    });

    test('pauze, verder, spoelen en volume', () async {
      await cast.playUrl(r, 'http://pc/stream/1.flac', title: 'Bad', artist: 'MJ', album: 'Bad', mime: 'audio/flac');
      await cast.pause(r);
      expect((await cast.transportState(r))!.state, 'PAUSED_PLAYBACK');
      await cast.play(r);
      expect(nest.speelt, isTrue);
      await cast.seek(r, const Duration(seconds: 90, milliseconds: 500));
      expect(nest.tijd, 90.5);
      expect(await cast.getVolume(r), 40);
      await cast.setVolume(r, 15);
      expect(nest.volume, closeTo(.15, 1e-9));
    });

    test('draait onze speler niet meer (iemand anders castte), dan bij het volgende nummer opnieuw starten', () async {
      nest.vergeetApp = true;
      await cast.playUrl(r, 'http://pc/stream/1.flac', title: 'a', artist: 'b', album: 'c', mime: 'audio/flac');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await cast.playUrl(r, 'http://pc/stream/2.flac', title: 'a', artist: 'b', album: 'c', mime: 'audio/flac');
      expect(nest.lanceringen, 2);
    });

    test('iemand anders castte terwijl wij speelden: het volgende nummer start onze speler opnieuw', () async {
      await cast.playUrl(r, 'http://pc/stream/1.flac', title: 'a', artist: 'b', album: 'c', mime: 'audio/flac');
      nest.andereCast();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await cast.playUrl(r, 'http://pc/stream/2.flac', title: 'a', artist: 'b', album: 'c', mime: 'audio/flac');
      expect(nest.lanceringen, 2);
    });

    test('draait onze speler al (de pc herstartte): meedoen, niet opnieuw starten', () async {
      nest.appDraait = true;
      await cast.playUrl(r, 'http://pc/stream/1.flac', title: 'a', artist: 'b', album: 'c', mime: 'audio/flac');
      expect(nest.lanceringen, 0);
      expect(nest.binnen.firstWhere((m) => m['type'] == 'LOAD')['_doel'], 'web-7');
    });

    test('valt de verbinding weg, dan de volgende keer een nieuwe', () async {
      await cast.playUrl(r, 'http://pc/stream/1.flac', title: 'a', artist: 'b', album: 'c', mime: 'audio/flac');
      for (final k in nest.klanten) {
        k.destroy();
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await cast.getVolume(r), 40);
      expect(nest.klanten.length, 2);
    });

    test('de Nest vraagt PING: wij zeggen PONG (anders sluit hij na ~10 s de verbinding)', () async {
      expect(await cast.getVolume(r), 40);
      nest._stuur(nest.klanten.single, 'receiver-0', kCastHartslag, {'type': 'PING'});
      for (var i = 0; i < 50 && !nest.binnen.any((m) => m['type'] == 'PONG'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final pong = nest.binnen.where((m) => m['type'] == 'PONG').single;
      expect(pong['_ns'], kCastHartslag);
      expect(pong['_doel'], 'receiver-0');
    });

    test('niets van ons op de speaker: geen plek, en "stopped"', () async {
      expect(await cast.positionInfo(r), isNull);
      expect((await cast.transportState(r))!.state, 'STOPPED');
      expect(nest.lanceringen, 0, reason: 'alleen kijken start niets');
    });
  });

  test('de standen in UPnP-woorden: IDLE (ook na het einde) is stopped', () {
    expect(castStand('PLAYING'), 'PLAYING');
    expect(castStand('PAUSED'), 'PAUSED_PLAYBACK');
    expect(castStand('BUFFERING'), 'TRANSITIONING');
    expect(castStand('IDLE'), 'STOPPED');
    expect(castStand(null), 'STOPPED');
  });

  test('aangesloten in de cast: Cast via zijn eigen bediening, elke seconde gevraagd, geen dubbele KEF', () {
    final s = File('lib/lan/cast_manager.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(s, contains('  UpnpControlPoint _voor(Renderer r) => isCast(r) ? _cast : (isKef(r) ? _kef : _upnp);\n'));
    expect(s, contains('  bool _snelVragen(Renderer r) => isKef(r) || isCast(r);\n'));
    expect(s, contains('          if (!alBekend.contains(c.host) || castAdres(c).poort != 8009) c.id: c,\n'));
    expect(s, contains('    _cast.sluit();\n'));
  });
}
