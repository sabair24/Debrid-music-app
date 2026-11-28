/// Bij een gewone wissel in een groep wacht de volger op de leider.
///
/// Saber, 28-11-2026, de Shield in een groep met de KEF LS50: bij bijna elke wissel sprong de Shield 0,2–0,35 s terug
/// (+251, +358, +215, +309, +274 ms gemeten) — *"ja dat stoort"*. Een KEF heeft geen klaargezet volgend nummer: de pc
/// start het pas als het vorige afgelopen is, en de KEF begint later dan de Shield, die zelf meteen doorging. Nu begint
/// de Shield het volgende nummer gepauzeerd en wacht hij zo lang als hij geleerd heeft (of tot het anker er is).
library;

import 'dart:io';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/samen.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

class _Speler implements VolgSpeler {
  _Speler(this.t);
  Track t;
  Duration plek = Duration.zero;
  final seeks = <Duration>[];
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
  void seek(Duration d) => seeks.add(d);
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

Track _nr(String id) => Track(path: '/m/$id.flac', title: id, artist: 'A', album: 'B');

void main() {
  late _Speler s;
  late SamenVolger v;
  late List<String> log;

  SamenVolger volger(FakeAsync fa) => SamenVolger(
      speler: s,
      nummer: _nr,
      idVan: (x) => x.title,
      klok: KlokIjk(),
      vertragingMs: () => 0,
      nuMs: () => 1000000 + fa.elapsed.inMilliseconds,
      log: log.add);

  /// Een anker van de KEF voor nummer [id] op [positieMs], gemeten met [onzeker] ms onzekerheid.
  SamenAnker anker(String id, int positieMs, {int onzeker = 5}) => SamenAnker(
      groep: 'spk:kef',
      trackId: id,
      rij: [id],
      index: 0,
      positieMs: positieMs,
      pcMs: KlokIjk().nuPcMs(),
      speelt: true,
      onzekerMs: onzeker);

  /// Een gewone wissel naar [id]: de speler vraagt de wachttijd en begint het nummer; de leider begint [later] ms later.
  void wissel(FakeAsync fa, String id, int later, {bool gewoon = true}) {
    // Zoals in de app: het nieuwe nummer staat er al als de speler naar de wachttijd vraagt.
    s
      ..t = _nr(id)
      ..plek = Duration(milliseconds: 300 + later);
    if (gewoon) v.wisselWacht();
    v.opAnker(anker(id, 300));
    fa.elapse(const Duration(milliseconds: 600));
  }

  setUp(() {
    s = _Speler(_nr('a'));
    log = [];
  });

  test('zonder groep geen wachten', () {
    fakeAsync((fa) {
      v = volger(fa);
      expect(v.wisselWacht(), Duration.zero);
    });
  });

  test('staat de leider stil, dan geen wachten (ook als er al iets geleerd is)', () {
    fakeAsync((fa) {
      v = volger(fa)..opAnker(anker('a', 60000));
      fa.elapse(const Duration(milliseconds: 600));
      wissel(fa, 'b', 250);
      expect(v.wisselWachtVoor('spk:kef'), greaterThan(0));
      v.opAnker(SamenAnker(
          groep: 'spk:kef', trackId: 'b', rij: const ['b'], index: 0, positieMs: 5000, pcMs: KlokIjk().nuPcMs(), speelt: false));
      expect(v.wisselWacht(), Duration.zero);
      v.stop(pauzeer: false);
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('alleen een meting van het nummer waarvoor hij wachtte, telt (niet van een nummer waar je daarna heen ging)', () {
    fakeAsync((fa) {
      v = volger(fa)..opAnker(anker('a', 60000));
      fa.elapse(const Duration(milliseconds: 600));
      s.t = _nr('c');
      v.wisselWacht();
      // Meteen terug naar b (zelf gekozen): de leider speelt b, deze speler ook, 250 ms verschil.
      s
        ..t = _nr('b')
        ..plek = const Duration(milliseconds: 550);
      v.opAnker(anker('b', 300));
      fa.elapse(const Duration(milliseconds: 600));
      expect(v.wisselWachtVoor('spk:kef'), 0);
      v.stop(pauzeer: false);
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('DE KERN: de KEF begint 250 ms later — de volger leert te wachten, en na een paar wissels klopt het', () {
    fakeAsync((fa) {
      v = volger(fa)..opAnker(anker('a', 60000));
      fa.elapse(const Duration(milliseconds: 600));
      expect(v.wisselWacht(), Duration.zero, reason: 'de eerste keer weet hij het nog niet');
      wissel(fa, 'b', 250);
      expect(v.wisselWachtVoor('spk:kef'), 200, reason: '0,8 × 250');
      expect(log.last, contains('wachten bij een wissel 200 ms'));
      // Volgende wissel: hij wachtte 200 ms, de KEF was nog 50 ms later.
      expect(v.wisselWacht(), const Duration(milliseconds: 200));
      wissel(fa, 'c', 50);
      // 200 + 0,8 × 50 (op een ms na: de klok van de toets loopt een fractie mee).
      final na = v.wisselWachtVoor('spk:kef');
      expect(na, closeTo(240, 2));
      // Een nummer dat je zelf koos (geen gewone wissel), 10 ms te vroeg: daar leert hij niets van.
      wissel(fa, 'd', 10, gewoon: false);
      expect(v.wisselWachtVoor('spk:kef'), na, reason: 'zonder gewone wissel (zelf gekozen) leert hij niets');
      v.stop(pauzeer: false);
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('een naadloze leider (Sonos): de volger is niet te vroeg, en het wachten blijft 0', () {
    fakeAsync((fa) {
      v = volger(fa)..opAnker(anker('a', 60000));
      fa.elapse(const Duration(milliseconds: 600));
      wissel(fa, 'b', -30);
      expect(v.wisselWachtVoor('spk:kef'), 0, reason: 'te laat is geen reden om te wachten');
      v.stop(pauzeer: false);
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('een onzekere meting leert niets; de eerste precieze wel, en na 15 s geen enkele meer', () {
    fakeAsync((fa) {
      v = volger(fa)..opAnker(anker('a', 60000));
      fa.elapse(const Duration(milliseconds: 600));
      s
        ..t = _nr('b')
        ..plek = const Duration(milliseconds: 550);
      v.wisselWacht();
      v.opAnker(anker('b', 300, onzeker: 70));
      fa.elapse(const Duration(milliseconds: 600));
      expect(v.wisselWachtVoor('spk:kef'), 0, reason: 'een grove meting na de wissel');
      v.opAnker(anker('b', 300));
      fa.elapse(const Duration(milliseconds: 600));
      expect(v.wisselWachtVoor('spk:kef'), greaterThan(150));
      // Te laat: een wissel waarvan pas na 15 s een precieze meting kwam.
      final voor = v.wisselWachtVoor('spk:kef');
      s
        ..t = _nr('c')
        ..plek = const Duration(milliseconds: 800);
      v.wisselWacht();
      fa.elapse(const Duration(seconds: 16));
      v.opAnker(anker('c', 300));
      fa.elapse(const Duration(milliseconds: 600));
      expect(v.wisselWachtVoor('spk:kef'), voor);
      v.stop(pauzeer: false);
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('de speler: na een gewone wissel gepauzeerd openen en na de wachttijd spelen; een tik begint meteen', () {
    final p = _bron('lib/player.dart');
    final einde = p.indexOf('      case NaHetEinde.volgende:');
    final rest = p.substring(einde, p.indexOf('\n  }\n', einde));
    expect(rest, contains('        if (!radioMode) _natuurlijkeWissel = true;\n        next();'));
    final open = p.indexOf('  Future<void> _openCurrent() async {');
    final lijf = p.substring(open, p.indexOf('\n  }\n', open));
    expect(lijf, contains('final wacht = _natuurlijkeWissel ? (wisselWacht?.call() ?? Duration.zero) : Duration.zero;'));
    expect(lijf, contains('    _natuurlijkeWissel = false;'));
    expect(lijf, contains('await _player.open(Media(bron), play: wacht <= Duration.zero);'));
    expect(lijf, contains('if (gen == _wisselGen && current?.path == t.path && !playing) unawaited(_player.play());'));
    final volgende = p.indexOf('  Future<void> next() async {');
    expect(p.substring(volgende, p.indexOf('\n  }\n', volgende)), contains('    _natuurlijkeWissel = false;'),
        reason: 'aan het eind van de rij blijft de vlag niet hangen tot een tik');
    expect(_bron('lib/main.dart'), contains('  player.wisselWacht = samenVolger.wisselWacht;'));
  });
}
