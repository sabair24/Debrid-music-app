// De groep Sonos Move + Shield na een herstart van de pc, en strakker springen bij een wissel (27-11-2026, live gemeten
// na 3.9.762):
//  * na de update van de pc was de groep weg — de Shield speelde vanaf het volgende nummer los, en om 10:14 klonken er
//    twee verschillende nummers in huis;
//  * een sprong landde gemiddeld ±50 ms te vroeg (vaste marge van 60 ms), en de eerste klokmeting na een wissel is ±70 ms.
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/samen.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

String bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

class _Speler implements VolgSpeler {
  _Speler(this.t);
  final Track t;
  Duration plek = Duration.zero;
  Duration Function(Duration doel)? naSprong;
  final seeks = <Duration>[];
  final snelheden = <double>[];
  @override
  bool playing = true;
  @override
  Track? get current => t;
  @override
  Duration get positieNauwkeurig => plek;
  @override
  List<Track> get queueTracks => [t];
  @override
  void pauzeer() => playing = false;
  @override
  void seek(Duration d) {
    seeks.add(d);
    final n = naSprong;
    if (n != null) plek = n(d);
  }

  @override
  void speelAf() => playing = true;
  @override
  Future<void> zetSnelheid(double v) async => snelheden.add(v);
  @override
  Future<void> neemOver(List<Track> r, int i, Duration positie,
      {bool spelen = true, bool shuffle = false, RepeatMode herhaal = RepeatMode.off}) async {}
  @override
  bool zetRijRondHuidig(List<Track> r, int i) => true;
}

void main() {
  group('de groep onthouden', () {
    late Directory map;
    late LanStateStore staat;
    late ZoneRegister reg;
    setUp(() {
      map = Directory.systemTemp.createTempSync('groep_onthouden_');
      staat = LanStateStore(File('${map.path}/state.json'));
      reg = ZoneRegister(state: staat, pcId: 'pc-THUIS', pcNaam: 'THUIS');
    });
    tearDown(() async {
      await reg.dispose();
      await staat.dispose();
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('elke wijziging gaat naar wie bewaart; terugzetten zet ze weer', () {
      final bewaard = <Map<String, List<String>>>[];
      reg.bijGroepen = bewaard.add;
      reg.zetToestelGroep('spk:move', ['shield']);
      expect(bewaard.last, {
        'spk:move': ['shield']
      });
      reg.zetToestelGroep('spk:move', const []);
      expect(bewaard.last, isEmpty, reason: 'opgeheven is ook een wijziging');

      final na = ZoneRegister(state: staat, pcId: 'pc-THUIS', pcNaam: 'THUIS');
      na.laadGroepen({
        'spk:move': ['shield', ''],
        'leeg': ['']
      });
      expect(na.toestelGroepen, {
        'spk:move': ['shield']
      });
      expect(na.leiderVan('shield'), 'spk:move');
      na.dispose();
    });

    test('de pc: een bewaarde groep staat er na het opstarten weer, en een nieuwe wordt bewaard', () async {
      File('${map.path}/zone_groepen.json').writeAsStringSync(jsonEncode({
        'spk:192.168.0.188': ['shield']
      }));
      final library = LibraryStore()
        ..rootPath = map.path
        ..configDirOverride = map.path;
      final server = LanServer(
        library: library,
        token: 'test-token',
        state: LanStateStore(File('${map.path}/state2.json')),
        pairing: PairingStore(),
        port: 0,
        version: '1',
      );
      try {
        expect(server.zones.toestelGroepen, {
          'spk:192.168.0.188': ['shield']
        });
        server.zones.zetToestelGroep('spk:192.168.0.188', ['shield', 'mac']);
        final terug = jsonDecode(File('${map.path}/zone_groepen.json').readAsStringSync()) as Map;
        expect(terug['spk:192.168.0.188'], ['shield', 'mac']);
      } finally {
        await server.dispose();
      }
    });
  });

  group('strakker springen', () {
    test('het anker draagt hoe zeker het is', () {
      const a = SamenAnker(
          groep: 'spk:move', trackId: 'x', rij: ['x'], index: 0, positieMs: 1000, pcMs: 5, speelt: true, onzekerMs: 67);
      final terug = SamenAnker.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>)!;
      expect(terug.onzekerMs, 67);
      expect(SamenAnker.fromJson({'trackId': 'x'})!.onzekerMs, 0, reason: 'een oudere pc: precies, zoals vroeger');
      final c = bron('lib/lan/cast_manager.dart');
      expect(c, contains("if (klok.schatting.breedteUs case final b?) 'onzekerMs': (b / 2000).round(),"));
    });

    Track nr(String id) => Track(path: '/m/$id.flac', title: id, artist: 'A', album: 'B');
    SamenVolger volger(_Speler s, FakeAsync fa) => SamenVolger(
        speler: s,
        nummer: (_) => s.t,
        idVan: (x) => x.title,
        klok: KlokIjk(),
        vertragingMs: () => 0,
        nuMs: () => 1000000 + fa.elapsed.inMilliseconds);
    SamenAnker anker(String id, int positieMs, {int onzeker = 0}) => SamenAnker(
        groep: 'spk:move',
        trackId: id,
        rij: [id],
        index: 0,
        positieMs: positieMs,
        pcMs: KlokIjk().nuPcMs(),
        speelt: true,
        onzekerMs: onzeker);

    test('de vroege sprong op een grove meting, en nog één als de meting precies wordt', () {
      fakeAsync((fa) {
        final t = nr('x');
        // De grove meting zat 80 ms naast: na de eerste sprong blijkt de speler (volgens de precieze) 80 ms voor.
        final s = _Speler(t)
          ..plek = const Duration(milliseconds: 2200)
          ..naSprong = (d) => d - const Duration(milliseconds: kSamenSpoelMarge);
        final v = volger(s, fa);
        v.opAnker(anker('x', 2000, onzeker: 67));
        fa.elapse(const Duration(milliseconds: 600));
        expect(s.seeks, hasLength(1));
        // Nu de precieze meting, die zegt dat het nummer 80 ms later is dan de grove dacht.
        s.plek = s.plek + const Duration(milliseconds: 80);
        fa.elapse(const Duration(seconds: 4));
        // (De speler in deze toets loopt niet door: het nieuwe anker staat op dezelfde plek, met een verse tijd.)
        v.opAnker(anker('x', 2000, onzeker: 5));
        fa.elapse(const Duration(milliseconds: 600));
        expect(s.seeks, hasLength(2), reason: 'de precieze meting mag nog één keer');
        fa.elapse(const Duration(seconds: 6));
        expect(s.seeks, hasLength(2), reason: 'daarna niet meer');
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('op een precieze meting maar één vroege sprong', () {
      fakeAsync((fa) {
        final t = nr('y');
        final s = _Speler(t)
          ..plek = const Duration(milliseconds: 2200)
          ..naSprong = (d) => d + const Duration(milliseconds: 60);
        final v = volger(s, fa);
        v.opAnker(anker('y', 2000, onzeker: 5));
        fa.elapse(const Duration(seconds: 6));
        expect(s.seeks, hasLength(1));
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('de marge leert bij uit wat er na een precieze sprong overblijft', () {
      fakeAsync((fa) {
        final t = nr('z');
        // Spoelen kost hier niets: de speler landt precies waar gevraagd, dus met de marge te ver.
        final s = _Speler(t)
          ..plek = const Duration(milliseconds: 2300)
          ..naSprong = (d) => d;
        final v = volger(s, fa);
        expect(v.spoelMarge, kSamenSpoelMarge);
        v.opAnker(anker('z', 2000, onzeker: 5));
        fa.elapse(const Duration(seconds: 3));
        expect(s.seeks, hasLength(1));
        expect(s.seeks.first.inMilliseconds, closeTo(2000 + kSamenSpoelMarge, 15), reason: 'gesprongen met de marge erbij');
        expect(v.spoelMarge, lessThan(kSamenSpoelMarge), reason: 'te ver geland: kleiner');
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('na een precieze sprong, maar met een grove meting erna: ook niets leren', () {
      fakeAsync((fa) {
        final t = nr('v');
        final s = _Speler(t)
          ..plek = const Duration(milliseconds: 2300)
          ..naSprong = (d) => d;
        final v = volger(s, fa);
        v.opAnker(anker('v', 2000, onzeker: 5));
        fa.elapse(const Duration(milliseconds: 600));
        expect(s.seeks, hasLength(1));
        v.opAnker(anker('v', 2000, onzeker: 67));
        fa.elapse(const Duration(seconds: 3));
        expect(v.spoelMarge, kSamenSpoelMarge);
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('na een grove sprong leert hij niets: die rest is de meting, niet het spoelen', () {
      fakeAsync((fa) {
        final t = nr('w');
        final s = _Speler(t)
          ..plek = const Duration(milliseconds: 2300)
          ..naSprong = (d) => d;
        final v = volger(s, fa);
        v.opAnker(anker('w', 2000, onzeker: 67));
        fa.elapse(const Duration(seconds: 3));
        expect(s.seeks, hasLength(1));
        expect(v.spoelMarge, kSamenSpoelMarge);
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });
  });
}
