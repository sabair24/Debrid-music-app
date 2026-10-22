/// De KEF via zijn eigen API (`lan/kef.dart`, 22-10-2026): Saber wil de LS50 Wireless II, en die antwoordde
/// niet meer als UPnP-speaker.
///
/// Wat hier vastligt: de spelopdracht in de vorm die op de echte KEF werkte (en hem 24/96 liet spelen); wat
/// de antwoorden van de KEF betekenen (in de vorm die hij echt stuurt); dat pauze en verder op de aan/uit-
/// knop alleen drukken als de stand het andere is (anders zet een tweede druk hem weer aan); dat hij eerst
/// naar de netwerkbron gaat; en de mDNS-vraag waarmee de pc hem vindt. Alles tegen een nep-KEF op
/// 127.0.0.1 — nooit tegen de echte.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/kef.dart';

/// Een KEF die opschrijft wat hij krijgt en antwoordt zoals de echte (vormen gemeten op 22-10-2026).
class _NepKef {
  late HttpServer server;
  String stand = 'stopped';
  String bron = 'wifi';
  int plek = -1;
  int volume = 21;
  final opdrachten = <Map<String, dynamic>>[];

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final res = req.response;
      if (req.uri.path == '/api/setData') {
        if (req.method != 'POST') {
          res.statusCode = 405;
          res.write('{"error":{"message":"Invalid method!"}}');
          await res.close();
          return;
        }
        final m = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        opdrachten.add(m);
        final v = m['value'];
        if (m['path'] == 'player:player/control' && v is Map) {
          switch (v['control']) {
            case 'play':
              if (v['mediaRoles'] == null) {
                res.statusCode = 500;
                stand = 'stopped';
              } else {
                stand = 'playing';
                plek = 0;
              }
            case 'pause':
              stand = stand == 'playing' ? 'paused' : (stand == 'paused' ? 'playing' : stand);
            case 'stop':
              stand = 'stopped';
            case 'seekTime':
              plek = v['time'] as int;
          }
        }
        if (m['path'] == 'settings:/kef/play/physicalSource' && v is Map) bron = '${v['kefPhysicalSource']}';
        if (m['path'] == 'player:volume' && v is Map) volume = v['i32_'] as int;
        res.write('null');
        await res.close();
        return;
      }
      final pad = req.uri.queryParameters['path'];
      res.write(switch (pad) {
        'settings:/deviceName' => '[{"type":"string_","string_":"LS50 Wireless II-1729d5"}]',
        'settings:/kef/host/modelName' => '[{"type":"string_","string_":"SP4025"}]',
        'settings:/kef/play/physicalSource' =>
          '[{"stability":0,"type":"kefPhysicalSource","kefPhysicalSource":"$bron"}]',
        'player:player/data/playTime' => '[{"type":"i64_","i64_":$plek}]',
        'player:volume' => '[{"type":"i32_","i32_":$volume}]',
        'player:player/data' => jsonEncode([
            {
              'state': stand,
              'status': {'timeSeek': true, 'duration': 279779},
              'trackRoles': {
                'type': 'audio',
                'title': 'Born In The U.S.A.',
                'mediaData': {
                  'resources': [
                    {'bitsPerSample': 24, 'mimeType': 'audio/flac', 'sampleFrequency': 96000, 'uri': 'http://pc/stream/x.flac'},
                  ],
                },
              },
            }
          ]),
        _ => '[]',
      });
      await res.close();
    });
  }

  List<String> get bediening => [
        for (final o in opdrachten)
          if (o['path'] == 'player:player/control') '${(o['value'] as Map)['control']}',
      ];
}

void main() {
  test('de spelopdracht: zoals op de echte KEF werkte (een audio-item met het adres als bron)', () {
    final o = kefSpeelOpdracht(
      uri: 'http://192.168.0.117:47820/stream/abc.flac?token=t',
      titel: 'Born In The U.S.A.',
      artiest: 'Bruce Springsteen',
      album: 'Born In The U.S.A.',
      mime: 'audio/flac',
      hoes: 'http://192.168.0.117:47820/art/1?token=t',
      duur: const Duration(seconds: 279),
    );
    expect(o['control'], 'play');
    final m = o['mediaRoles'] as Map;
    expect(m['type'], 'audio');
    expect(m['title'], 'Born In The U.S.A.');
    final media = m['mediaData'] as Map;
    expect((media['metaData'] as Map)['artist'], 'Bruce Springsteen');
    expect((media['metaData'] as Map)['albumCoverUri'], 'http://192.168.0.117:47820/art/1?token=t');
    final bron = (media['resources'] as List).single as Map;
    expect(bron['uri'], 'http://192.168.0.117:47820/stream/abc.flac?token=t');
    expect(bron['mimeType'], 'audio/flac');
    expect(bron['duration'], 279000);
    // Zonder hoes geen leeg veld.
    expect(((kefSpeelOpdracht(uri: 'u', titel: 't', artiest: 'a', album: 'b', mime: 'audio/flac')['mediaRoles']
                as Map)['mediaData'] as Map)['metaData'],
        isNot(contains('albumCoverUri')));
  });

  test('de antwoorden van de KEF lezen (in de vorm die hij stuurt)', () {
    expect(kefGetal('[{"type":"i64_","i64_":22198}]'), 22198);
    expect(kefGetal('[{"type":"i32_","i32_":7}]'), 7);
    expect(kefGetal('{"error":{"message":"Node at path does not exist"}}'), isNull);
    final s = kefSpeler(jsonEncode([
      {
        'state': 'paused',
        'status': {'duration': 279779},
        'trackRoles': {
          'mediaData': {
            'resources': [
              {'uri': 'http://pc/stream/x.flac', 'sampleFrequency': 96000},
            ],
          },
        },
      }
    ]));
    expect(s.stand, 'paused');
    expect(s.duurMs, 279779);
    expect(s.uri, 'http://pc/stream/x.flac');
    expect(kefSpeler('[]').stand, '');
  });

  test('de mDNS-vraag naar _kef-info._tcp.local, en een antwoord herkennen', () {
    final v = mdnsVraag('_kef-info._tcp.local');
    expect(v.sublist(0, 12), [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0], reason: 'één vraag');
    expect(latin1.decode(v.sublist(12)), '\u0009_kef-info\u0004_tcp\u0005local\u0000\u0000\u000c\u0000\u0001');
    expect(mdnsNoemt(latin1.encode('xx _kef-info yy'), '_kef-info'), isTrue);
    expect(mdnsNoemt(latin1.encode('_airplay _raop'), '_kef-info'), isFalse);
  });

  group('de bediening, tegen een nep-KEF', () {
    late _NepKef kef;
    late KefBediening b;
    late dynamic r;

    setUp(() async {
      kef = _NepKef();
      await kef.start();
      b = KefBediening(poort: kef.server.port);
      r = kefRenderer(host: '127.0.0.1', naam: 'LS50 Wireless II-1729d5');
    });

    tearDown(() async {
      b.sluit();
      await kef.server.close(force: true);
    });

    test('spelen gaat eerst naar de netwerkbron, en stuurt het adres', () async {
      kef.bron = 'optic';
      await b.playUrl(r, 'http://pc/stream/x.flac?token=t',
          title: 'T', artist: 'A', album: 'B', mime: 'audio/flac', duration: const Duration(seconds: 200));
      expect(kef.opdrachten.first['path'], 'settings:/kef/play/physicalSource');
      expect(kef.bron, 'wifi');
      final speel = kef.opdrachten.last;
      expect(speel['path'], 'player:player/control');
      expect(speel['role'], 'activate');
      expect(((((speel['value'] as Map)['mediaRoles'] as Map)['mediaData'] as Map)['resources'] as List).single['uri'],
          'http://pc/stream/x.flac?token=t');
      expect((await b.transportState(r))!.state, 'PLAYING');
      // Al op het netwerk: geen bronwissel.
      kef.opdrachten.clear();
      await b.playUrl(r, 'u', title: 'T', artist: 'A', album: 'B', mime: 'audio/flac');
      expect([for (final o in kef.opdrachten) o['path']], ['player:player/control']);
    });

    test('pauze en verder drukken de aan/uit-knop alleen als de stand het andere is', () async {
      await b.playUrl(r, 'u', title: 'T', artist: 'A', album: 'B', mime: 'audio/flac');
      kef.opdrachten.clear();
      await b.play(r); // speelt al: niets
      expect(kef.bediening, isEmpty);
      await b.pause(r);
      expect(kef.stand, 'paused');
      await b.pause(r); // staat al op pauze: niet nog eens (dat zou hem weer aanzetten)
      expect(kef.stand, 'paused');
      expect(kef.bediening, ['pause']);
      await b.play(r);
      expect(kef.stand, 'playing');
      expect(kef.bediening, ['pause', 'pause']);
      expect((await b.transportState(r))!.state, 'PLAYING');
      await b.stop(r);
      expect((await b.transportState(r))!.state, 'STOPPED');
      // Gestopt: verder kan niet (play zonder nummer zou hem leegmaken) — er gaat niets uit.
      kef.opdrachten.clear();
      await b.play(r);
      expect(kef.bediening, isEmpty);
    });

    test('spoelen in ms, de plek in ms, de lengte, en het volume', () async {
      await b.playUrl(r, 'u', title: 'T', artist: 'A', album: 'B', mime: 'audio/flac');
      kef.plek = -1;
      expect((await b.positionInfo(r))!.position, isNull, reason: '-1 vlak na de start is: nog niet bekend');
      await b.seek(r, const Duration(milliseconds: 120000));
      expect((kef.opdrachten.last['value'] as Map)['time'], 120000);
      kef.plek = 120432;
      final p = (await b.positionInfo(r))!;
      expect(p.position, const Duration(milliseconds: 120432));
      expect(p.duration, const Duration(milliseconds: 279779));
      expect(p.trackUri, 'http://pc/stream/x.flac');
      expect(await b.getVolume(r), 21);
      await b.setVolume(r, 30);
      expect(kef.volume, 30);
      expect(kef.opdrachten.last['value'], {'type': 'i32_', 'i32_': 30});
    });

    test('naam en model via de API (zo vult het zoeken de speaker in)', () async {
      final api = KefApi('127.0.0.1', poort: kef.server.port);
      expect(await api.naam(), 'LS50 Wireless II-1729d5');
      expect(await api.model(), 'SP4025');
      api.sluit();
      expect(isKef(r), isTrue);
      expect(r.id, '127.0.0.1');
    });
  });
}
