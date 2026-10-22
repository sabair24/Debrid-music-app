/// Toestellen die met een Sonos meespelen (groeperen, stap 3.3, Saber 21-10-2026: "pc + Sonos ongeveer,
/// met een schuif").
///
/// Wat hier vastligt: de cast zegt waar de Sonos is, op enkele ms, zolang er toestellen meespelen; een
/// pauze, spoelen of een ander nummer hoort de volger meteen ("stil daar"), niet pas als de klok het merkt;
/// zolang de speaker nog laadt en spoelt komt er geen anker; en bij een naadloze overgang noemt het anker
/// nooit het ene nummer met de plek van het andere. Op de pc: de speaker draagt de namen van wie
/// meespeelt, die staan er niet apart in, en de schuif schuift het anker. Over de lijn: een groep met een
/// speaker maken, het anker bij de volger, de schuif, en los = samenStop.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/cast_manager.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/upnp.dart';
import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/samen.dart';

const _t = 1760000000000000; // µs

/// Een Sonos zoals de Move (gemeten 22-10-2026): na het openen ~430 ms niets, dan speelt hij; na spoelen
/// en na verder spelen buffert hij even; hij meldt hele seconden; het volgende nummer (SetNext) begint
/// naadloos waar het vorige ophoudt.
class _Sonos extends UpnpControlPoint {
  _Sonos(this.nu);

  final int Function() nu;
  int duurUs = 200000000;

  /// De vraag direct na die waarin hij de wissel liet zien, duurt 2,5 s (zo vraagt de pc zelf welk nummer
  /// er nu speelt, bij een trage speaker).
  bool traagNaWissel = false;
  int _vragen = 0;
  int? _wisselBij;

  int beginUs = 0;
  int? stilUs = 0;
  int? hervatOp;
  bool gepauzeerd = false;
  String? uri, volgende;
  final opdrachten = <String>[];

  String _id(String? url) => url == null ? '-' : RegExp(r'/stream/([^/.?]+)').firstMatch(url)?.group(1) ?? url;

  /// Het nummer dat hij nu speelt (id uit de URL).
  String get speelt => _id(uri);

  int positieUs() {
    final t = nu();
    if (hervatOp != null && t >= hervatOp!) {
      beginUs = hervatOp! - stilUs!;
      stilUs = null;
      hervatOp = null;
    }
    if (stilUs != null) return stilUs!;
    var p = t - beginUs;
    if (p >= duurUs && volgende != null) {
      beginUs += duurUs;
      _wisselBij = _vragen;
      uri = volgende;
      volgende = null;
      p = t - beginUs;
    }
    return p;
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
      Duration? duration}) async {
    opdrachten.add('open $title');
    uri = url;
    volgende = null;
    stilUs = 0;
    gepauzeerd = false;
    hervatOp = nu() + 430000;
  }

  @override
  Future<void> setNextUrl(Renderer renderer, String url,
      {required String title,
      required String artist,
      required String album,
      required String mime,
      String? artUrl,
      Duration? duration}) async {
    volgende = url;
  }

  @override
  Future<void> play(Renderer r) async {
    positieUs();
    opdrachten.add('play');
    if (gepauzeerd) {
      gepauzeerd = false;
      hervatOp = nu() + 200000;
    }
  }

  @override
  Future<void> pause(Renderer r) async {
    stilUs = positieUs();
    hervatOp = null;
    gepauzeerd = true;
    opdrachten.add('pause');
  }

  @override
  Future<void> seek(Renderer r, Duration to) async {
    positieUs();
    opdrachten.add('seek ${to.inSeconds}');
    stilUs = to.inMicroseconds;
    hervatOp = gepauzeerd ? null : nu() + 300000;
  }

  @override
  Future<int?> getVolume(Renderer r) async => 40;

  @override
  Future<({Duration? position, Duration duration, String? trackUri})?> positionInfo(Renderer r) async {
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final nr = ++_vragen;
    final p = positieUs();
    final u = uri;
    final traag = traagNaWissel && _wisselBij != null && nr == _wisselBij! + 1;
    await Future<void>.delayed(Duration(milliseconds: traag ? 2500 : 2));
    return (position: Duration(seconds: max(0, p) ~/ 1000000), duration: const Duration(seconds: 200), trackUri: u);
  }

  @override
  Future<TransportState?> transportState(Renderer r) async =>
      TransportState(gepauzeerd ? 'PAUSED_PLAYBACK' : 'PLAYING');
}

const _move = Renderer(
    id: '192.168.0.188',
    name: 'Sonos Move',
    host: '192.168.0.188',
    avTransportUrl: 'http://192.168.0.188:1400/av',
    manufacturer: 'Sonos, Inc.',
    udn: 'RINCON_MOVE');

void main() {
  group('de cast, als er toestellen met de speaker meespelen', () {
    late Directory map;
    late LanCatalog catalog;
    late List<String> ids;

    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_samen_spk_');
      final library = LibraryStore()..rootPath = map.path;
      library.tracks.addAll([
        for (final n in ['Een', 'Twee', 'Drie'])
          Track(
            path: '${map.path}/A/Album/$n.flac',
            title: n,
            artist: 'A',
            album: 'Album',
            trackNo: 1,
            duration: const Duration(seconds: 200),
            isFlac: true,
            sizeBytes: 1000,
            sampleRate: 44100,
            bitsPerSample: 16,
          ),
      ]);
      library.rebuildAlbums();
      catalog = LanCatalog(library);
      ids = [for (final t in catalog.snapshot().catalog.tracks) t.id];
    });

    tearDown(() {
      catalog.dispose();
      map.deleteSync(recursive: true);
    });

    ({CastManager cast, _Sonos sonos, List<Map<String, dynamic>> ankers, int Function() nuMs}) maak(FakeAsync fa, {int zaad = 1}) {
      int nu() => _t + fa.elapsed.inMicroseconds;
      final sonos = _Sonos(nu);
      final ankers = <Map<String, dynamic>>[];
      final cast = CastManager(
        catalog: catalog,
        token: 't',
        port: 47820,
        upnp: sonos,
        startGrace: Duration.zero,
        klokUs: nu,
        adresVoor: (_) async => '192.168.0.117',
        toeval: Random(zaad),
      )..kenSpeakersVoorToets([_move]);
      cast.bijAnker = (id) {
        final a = cast.ankerVan(id);
        if (a != null) ankers.add(a);
      };
      cast.volgKlok(_move.id, true);
      return (cast: cast, sonos: sonos, ankers: ankers, nuMs: () => nu() ~/ 1000);
    }

    /// Hoe ver het anker, doorgerekend tot nu, van de echte plek van de speaker af zit (ms).
    int fout(Map<String, dynamic> a, _Sonos s, int nuMs) {
      final p = (a['positieMs'] as int) + (a['speelt'] == true ? nuMs - (a['pcMs'] as int) : 0);
      return p - s.positieUs() ~/ 1000;
    }

    // Gemeten over 300 zaden (22-10-2026): de grootste afwijking van het laatste anker, in seconden na het
    // spoelen, 2 s 65 ms · 3 s 37 · 4 s 22 · 5 s 11 · 6–8 s 7 · daarna 4–5 ms. Vandaar: na zeven seconden
    // binnen 10 ms. (Na vier seconden binnen 10 ms wankelde: 38 van de 300 zaden lagen op 10–14 ms.)

    test('het anker zegt waar hij is, op enkele ms; een pauze hoort de volger meteen', () {
      fakeAsync((fa) {
        final m = maak(fa);
        unawaited(m.cast.play(_move.id, [ids[0], ids[1]], 0, alsZone: true));
        fa.flushMicrotasks();
        // Meteen: wacht op het begin.
        expect(m.ankers.last['speelt'], isFalse);
        expect(m.ankers.last['positieMs'], 0);
        expect(m.ankers.last['trackId'], ids[0]);
        expect(m.ankers.last['groep'], 'spk:${_move.id}');

        fa.elapse(const Duration(seconds: 8));
        expect(m.ankers.last['speelt'], isTrue);
        expect(fout(m.ankers.last, m.sonos, m.nuMs()).abs(), lessThan(10));

        // Pauze: meteen stil, op de plek van nu.
        final voor = m.ankers.length;
        unawaited(m.cast.control(_move.id, 'pause'));
        fa.flushMicrotasks();
        expect(m.ankers.length, greaterThan(voor));
        expect(m.ankers.last['speelt'], isFalse);
        expect(((m.ankers.last['positieMs'] as int) - m.sonos.positieUs() ~/ 1000).abs(), lessThan(20));
        fa.elapse(const Duration(seconds: 5));
        expect(m.ankers.last['speelt'], isFalse, reason: 'hij staat nog stil');

        // Verder: speelt weer, op de goede plek.
        unawaited(m.cast.control(_move.id, 'play'));
        fa.elapse(const Duration(seconds: 8));
        expect(m.ankers.last['speelt'], isTrue);
        expect(fout(m.ankers.last, m.sonos, m.nuMs()).abs(), lessThan(10));
        m.cast.dispose();
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('beginnen op een plek: geen anker zolang hij laadt en spoelt, dan stil daar, dan speelt hij', () {
      fakeAsync((fa) {
        final m = maak(fa);
        unawaited(m.cast.play(_move.id, [ids[0]], 0, alsZone: true, vanafMs: 60000));
        fa.flushMicrotasks();
        for (var i = 0; i < 29; i++) {
          fa.elapse(const Duration(milliseconds: 100));
          // Ook wie er zelf om vraagt (een volger die opnieuw verbindt), krijgt niets.
          expect(m.cast.ankerVan(_move.id), isNull, reason: 'na ${i * 100 + 100} ms');
        }
        expect(m.ankers, isEmpty, reason: 'hij laadt nog (en speelt vanaf 0): wie meespeelt, speelt door');
        fa.elapse(const Duration(milliseconds: 200));
        expect(m.sonos.opdrachten, contains('seek 63'));
        expect(m.ankers.first['speelt'], isFalse);
        expect(m.ankers.first['positieMs'], 63000);
        fa.elapse(const Duration(seconds: 7));
        expect(m.ankers.last['speelt'], isTrue);
        expect(fout(m.ankers.last, m.sonos, m.nuMs()).abs(), lessThan(10));
        m.cast.dispose();
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    for (final (naam, duur, traag) in [
      ('op een hele seconde: de speakerklok ziet de wissel eerst', 200000000, false),
      // De wissel valt 100 ms voor de tijdklok van vijf seconden, en 400 ms voor de volgende vraag van de
      // speakerklok (echte nummers duren geen hele seconden).
      ('na 199,6 s: de tijdklok ziet de wissel eerst', 199600000, false),
      ('een trage speaker: de pc weet nog niet welk nummer er speelt', 200000000, true),
    ]) {
      test('naadloos naar het volgende nummer, $naam — nooit het ene nummer met de plek van het andere', () {
        fakeAsync((fa) {
          final m = maak(fa);
          m.sonos
            ..duurUs = duur
            ..traagNaWissel = traag;
          // Tien seconden voor het eind beginnen: rond 10 s gaat hij naadloos naar het volgende nummer.
          unawaited(m.cast.play(_move.id, [ids[0], ids[1]], 0, alsZone: true, vanafMs: 190000));
          fa.flushMicrotasks();
          void klopt(Map<String, dynamic>? a, String wie) {
            if (a == null) return;
            final p = (a['positieMs'] as int) + (a['speelt'] == true ? m.nuMs() - (a['pcMs'] as int) : 0);
            if (a['trackId'] == ids[0]) {
              expect(p, greaterThan(150000), reason: '$wie: het eerste nummer met een plek aan het begin');
            } else {
              expect(p, lessThan(20000), reason: '$wie: het tweede nummer met een plek aan het eind');
            }
          }

          for (var i = 0; i < 2000; i++) {
            fa.elapse(const Duration(milliseconds: 10));
            if (m.ankers.isNotEmpty) klopt(m.ankers.last, 'gemeld');
            // Ook wie er zelf om vraagt, op elk moment.
            klopt(m.cast.ankerVan(_move.id), 'gevraagd na ${(i + 1) * 10} ms');
          }
          expect(m.sonos.speelt, ids[1]);
          expect(m.ankers.last['trackId'], ids[1]);
          expect(m.ankers.last['speelt'], isTrue);
          expect(fout(m.ankers.last, m.sonos, m.nuMs()).abs(), lessThan(15));
          m.cast.dispose();
          fa.flushTimers(flushPeriodicTimers: false);
        });
      });
    }

    test('geen meespelers: geen klok, geen anker', () {
      fakeAsync((fa) {
        final m = maak(fa);
        m.cast.volgKlok(_move.id, false);
        unawaited(m.cast.play(_move.id, [ids[0]], 0, alsZone: true));
        fa.elapse(const Duration(seconds: 5));
        expect(m.ankers, isEmpty);
        expect(m.cast.ankerVan(_move.id), isNull);
        m.cast.dispose();
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });
  });

  group('op de pc', () {
    late Directory map;
    late LanStateStore staat;
    late ZoneRegister reg;

    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_samen_spk_reg_');
      staat = LanStateStore(File('${map.path}/state.json'));
      reg = ZoneRegister(state: staat, pcId: 'pc-THUIS', pcNaam: 'THUIS');
    });

    tearDown(() async {
      await reg.dispose();
      await staat.dispose();
      map.deleteSync(recursive: true);
    });

    test('de speaker draagt de namen van wie meespeelt; die staan er niet apart in; de schuif schuift het anker',
        () {
      reg.zetSpeakers(const [], bekend: [(id: '192.168.0.188', naam: 'Sonos Move', sonos: true)]);
      reg.stroomOpen('gsm', naam: 'Galaxy', soort: ZoneSoort.gsm);
      expect(reg.zetToestelGroep('spk:192.168.0.188', ['pc-THUIS', 'gsm']), isEmpty);
      final z = {for (final x in reg.lijst()) x.id: x};
      expect(z['spk:192.168.0.188']!.naam, 'Sonos Move + THUIS + Galaxy');
      expect(z['spk:192.168.0.188']!.groep, ['spk:192.168.0.188', 'dev:pc-THUIS', 'dev:gsm']);
      expect(z.containsKey('dev:pc-THUIS'), isFalse);
      expect(z.containsKey('dev:gsm'), isFalse);
      expect(reg.leiderVan('pc-THUIS'), 'spk:192.168.0.188');

      reg.speakerAnker = (id) => {
            'groep': 'spk:$id',
            'trackId': 't',
            'rij': ['t'],
            'index': 0,
            'positieMs': 60000,
            'pcMs': 1000,
            'speelt': true,
          };
      expect(reg.ankerVan('spk:192.168.0.188')!['positieMs'], 60000);
      // De Sonos klinkt 150 ms later dan hij zegt: wie meespeelt, ook.
      reg.zetSpeakerVertraging('192.168.0.188', 150);
      final a = SamenAnker.fromJson(reg.ankerVan('spk:192.168.0.188'))!;
      expect(a.positieMs, 59850);
      expect(a.groep, 'spk:192.168.0.188');
      expect({for (final x in reg.lijst()) x.id: x}['spk:192.168.0.188']!.samenMs, 150);
      // Heen en terug over de lijn.
      expect(ZoneStaat.fromJson(z['spk:192.168.0.188']!.toJson()), z['spk:192.168.0.188']);
    });
  });

  group('over de lijn', () {
    late Directory map;
    late LanServer server;
    late RemoteClient c;

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_samen_spk_srv_');
      server = LanServer(
        library: LibraryStore()..rootPath = map.path,
        token: 'sleutel',
        state: LanStateStore(File('${map.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
      );
      expect(await server.start(), isNull);
      c = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:${server.boundPort}'), token: 'sleutel'));
    });

    tearDown(() async {
      c.close();
      await server.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      map.deleteSync(recursive: true);
    });

    test('een groep met een speaker: het anker van de speaker bij de volger, met de schuif; los = samenStop',
        () async {
      final events = <SseEvent>[];
      final sub = c.zoneStroom(toestel: 'gsm-1', naam: 'Galaxy').listen(events.add);
      for (var i = 0; i < 50 && server.zones.bereikbareToestellen().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      List<Map<String, dynamic>> cmds() => [
            for (final e in events.where((e) => e.event == 'cmd')) jsonDecode(e.data) as Map<String, dynamic>,
          ];
      Future<void> tot(bool Function() klaar) async {
        for (var i = 0; i < 100 && !klaar(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      final r = await c.ask('/api/zone/cmd', {
        'zone': 'spk:192.168.0.188',
        'cmd': 'groepeer',
        'leden': ['dev:gsm-1'],
      });
      expect(r['leider'], 'spk:192.168.0.188');
      expect(server.zones.leiderVan('gsm-1'), 'spk:192.168.0.188');

      // De speakerklok meldt waar hij is.
      server.zones.speakerAnker = (id) => {
            'groep': 'spk:$id',
            'trackId': 't7',
            'rij': ['t6', 't7'],
            'index': 1,
            'positieMs': 30000,
            'pcMs': DateTime.now().millisecondsSinceEpoch,
            'speelt': true,
          };
      server.cast.bijAnker!('192.168.0.188');
      await tot(() => cmds().any((m) => m['cmd'] == 'samen'));
      final a = SamenAnker.fromJson((cmds().last['anker'] as Map).cast<String, dynamic>())!;
      expect(a.groep, 'spk:192.168.0.188');
      expect(a.trackId, 't7');
      expect(a.positieMs, 30000);

      // De schuif: meteen een nieuw anker, zoveel later.
      final n = cmds().length;
      await c.ask('/api/zone/cmd', {'zone': 'spk:192.168.0.188', 'cmd': 'samenVertraging', 'ms': 200});
      await tot(() => cmds().length > n);
      expect(SamenAnker.fromJson((cmds().last['anker'] as Map).cast<String, dynamic>())!.positieMs, 29800);
      expect(server.zones.speakerVertraging, {'192.168.0.188': 200});

      // Los: de gsm hoort dat hij niet meer volgt.
      await c.ask('/api/zone/cmd', {'zone': 'spk:192.168.0.188', 'cmd': 'groepeer', 'leden': <String>[]});
      await tot(() => cmds().any((m) => m['cmd'] == 'samenStop'));
      expect(cmds().last['cmd'], 'samenStop');
      expect(server.zones.leiderVan('gsm-1'), isNull);
      await sub.cancel();
    });
  });
}
