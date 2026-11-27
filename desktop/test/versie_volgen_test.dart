/// De volger in een groep speelt dezelfde versie als de leider.
///
/// Saber, 27-11-2026, 08:49:26: op de Mac "Underneath Your Clothes" van Shakira op de Sonos naar de cd gewisseld
/// (cast.log: `versie op Sonos Move: … op 208s`). De Shield, die de Sonos volgde, bleef op de vinylrip: het anker noemde
/// alleen het nummer, niet de versie, en "zelfde nummer" was voor de volger genoeg.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/samen.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

class _Speler implements VolgSpeler {
  _Speler(this.t);
  final Track t;
  @override
  bool playing = true;
  @override
  Track? get current => t;
  @override
  Duration get positieNauwkeurig => const Duration(seconds: 208);
  @override
  List<Track> get queueTracks => [t];
  @override
  void pauzeer() => playing = false;
  @override
  void seek(Duration d) {}
  @override
  void speelAf() => playing = true;
  @override
  Future<void> zetSnelheid(double v) async {}
  @override
  Future<void> neemOver(List<Track> r, int i, Duration positie,
      {bool spelen = true, bool shuffle = false, RepeatMode herhaal = RepeatMode.off}) async {}
  @override
  bool zetRijRondHuidig(List<Track> r, int i) => true;
}

Track _nr(String id, {String album = 'Laundry Service'}) =>
    Track(path: '/m/$id.flac', title: 'Underneath Your Clothes', artist: 'Shakira', album: album);

void main() {
  final vinyl = _nr('vinyl', album: 'Laundry Service (vinyl)');
  final cd = _nr('cd');
  final nummers = {'vinyl': vinyl, 'cd': cd};

  SamenAnker anker({String speelId = 'cd'}) => SamenAnker(
        groep: 'spk:move',
        trackId: 'vinyl',
        speelId: speelId,
        rij: const ['vinyl'],
        index: 0,
        positieMs: 208000,
        pcMs: KlokIjk().nuPcMs(),
        speelt: true,
      );

  ({SamenVolger volger, List<String> gekozen, List<String> log}) opzet(FakeAsync fa,
      {String Function()? speelPad, Future<void> Function(String)? kies, bool zonderVersie = false}) {
    final gekozen = <String>[];
    final log = <String>[];
    final v = SamenVolger(
      speler: _Speler(vinyl),
      nummer: (id) => nummers[id],
      idVan: (t) => nummers.entries.firstWhere((e) => e.value.path == t.path).key,
      klok: KlokIjk(),
      vertragingMs: () => 0,
      nuMs: () => 1000000 + fa.elapsed.inMilliseconds,
      log: log.add,
      speelPad: zonderVersie ? null : (speelPad ?? () => vinyl.path),
      kiesVersie: zonderVersie
          ? null
          : (kies ??
              (pad) async {
                gekozen.add(pad);
              }),
    );
    return (volger: v, gekozen: gekozen, log: log);
  }

  test('het anker draagt de versie die de leider echt speelt; een oudere pc geeft er geen', () {
    final a = anker();
    final terug = SamenAnker.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>)!;
    expect(terug.speelId, 'cd');
    expect(SamenAnker.fromJson({'trackId': 'x'})!.speelId, '');
    expect(_bron('lib/lan/cast_manager.dart'), contains("'speelId': _speelId(s, s.index, tid),"));
  });

  test('de leider speelt de cd, hier klinkt de vinylrip: de volger kiest de cd', () {
    fakeAsync((fa) {
      final o = opzet(fa);
      unawaited(o.volger.opAnker(anker()));
      fa.flushMicrotasks();
      expect(o.gekozen, [cd.path]);
      expect(o.log.last, contains('andere versie'));
      unawaited(o.volger.stop(pauzeer: false));
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('dezelfde versie, geen versie in het anker, of een versie die hier niet staat: niets', () {
    fakeAsync((fa) {
      final zelfde = opzet(fa, speelPad: () => cd.path);
      unawaited(zelfde.volger.opAnker(anker()));
      final oud = opzet(fa);
      unawaited(oud.volger.opAnker(anker(speelId: '')));
      final onbekend = opzet(fa);
      unawaited(onbekend.volger.opAnker(anker(speelId: 'weg')));
      final zonder = opzet(fa, zonderVersie: true);
      unawaited(zonder.volger.opAnker(anker()));
      fa.flushMicrotasks();
      expect(zelfde.gekozen, isEmpty);
      expect(oud.gekozen, isEmpty);
      expect(onbekend.gekozen, isEmpty);
      for (final o in [zelfde, oud, onbekend, zonder]) {
        unawaited(o.volger.stop(pauzeer: false));
      }
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('een trage wissel: een tweede anker intussen wisselt niet nog eens', () {
    fakeAsync((fa) {
      final klaar = Completer<void>();
      var keer = 0;
      final o = opzet(fa, kies: (_) {
        keer++;
        return klaar.future;
      });
      unawaited(o.volger.opAnker(anker()));
      fa.flushMicrotasks();
      unawaited(o.volger.opAnker(anker()));
      fa.flushMicrotasks();
      expect(keer, 1);
      klaar.complete();
      fa.flushMicrotasks();
      unawaited(o.volger.opAnker(anker()));
      fa.flushMicrotasks();
      expect(keer, 2, reason: 'klaar, en hier klinkt (in deze nep) nog altijd de vinylrip: opnieuw');
      unawaited(o.volger.stop(pauzeer: false));
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('de speler opent de versie van de leider op dezelfde plek, en de app sluit het aan', () {
    final p = _bron('lib/player.dart');
    final i = p.indexOf('Future<void> volgVersie(String pad) async {');
    expect(i, greaterThan(0));
    final lijf = p.substring(i, p.indexOf('\n  }\n', i));
    expect(lijf, contains('if (t == null || _speelPad(t.path) == pad) return;'));
    expect(lijf, contains('_versieGekozen = (anker: t.path, pad: pad);'));
    expect(lijf, contains('await _hervatOpDezelfdePlek();'));
    final m = _bron('lib/main.dart');
    expect(m, contains('speelPad: () => player.speelPad,'));
    expect(m, contains('kiesVersie: player.volgVersie,'));
  });
}
