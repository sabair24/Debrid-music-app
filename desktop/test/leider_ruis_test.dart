/// De volger jaagt niet op de ruis van de leider.
///
/// Saber, 28-11-2026, met de Shield in een groep met de KEF LS50: *"ik hoor een zakking in tempo"*. De KEF meldt zijn
/// plek eens per seconde, in stappen van 48 ms, met een sprongmoment dat ±35 ms schuift; de pc rekende elke meting als
/// ±2 ms precies. De Shield stuurde op elke meting vanaf 20 ms met 1 % bij: in 70 s veertien keer tussen 0,990 en 1,010.
/// Nu: de plek van de leider uit de mediaan van de laatste vijf ankers, drempels op de gemeten ruis, en zacht bijsturen.
library;

import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/samen.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class _Speler implements VolgSpeler {
  _Speler(this.t);
  final Track t;
  Duration plek = const Duration(seconds: 60);
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
  void seek(Duration d) => seeks.add(d);
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

/// Wat de KEF op 28-11-2026 om 14:00 meldde, min de rechte lijn: de ruis van zijn plek per meting (ms).
const _kefRuis = [72, 14, -5, 46, 2, 13, 8, 11, 6, 26, 5, -45, 4, -11, 61, 0, 6, 22, 10, -30, -52, -33, 17, 12, 19, -16];

void main() {
  group('de rekenregels', () {
    test('mediaan en ruis', () {
      expect(mediaan([5, -40, 3]), 3);
      expect(mediaan([1, 2, 3, 4]), 3);
      expect(ruisUit(const [10]), 0, reason: 'één verschil zegt niets');
      expect(ruisUit(const [10, -10, 10, -10]), 7, reason: 'σ√2 = 10');
    });

    test('zacht: 20 ms is 0,2 %, pas vanaf 100 ms de volle 1 %; de drempels rekken mee', () {
      expect(bijsturing(-20).snelheid, closeTo(1.002, 1e-9));
      expect(bijsturing(50).snelheid, closeTo(0.995, 1e-9));
      expect(bijsturing(140).snelheid, closeTo(0.99, 1e-9));
      expect(bijsturing(30, drempel: 40).snelheid, 1.0, reason: 'onder de ruis van de leider: niets doen');
      expect(bijsturing(30, bezig: true, goed: 35).snelheid, 1.0);
      expect(bijsturing(60, begin: true, spoelBegin: 70).spoel, isFalse);
      expect(bijsturing(60, begin: true).spoel, isTrue);
    });
  });

  group('de volger', () {
    final t = Track(path: '/m/x.flac', title: 'x', artist: 'A', album: 'B');
    SamenVolger volger(_Speler s, FakeAsync fa) => SamenVolger(
        speler: s,
        nummer: (_) => t,
        idVan: (x) => x.title,
        klok: KlokIjk(),
        vertragingMs: () => 0,
        nuMs: () => 1000000 + fa.elapsed.inMilliseconds);

    /// Een anker [i] van de leider: in werkelijkheid op 60 s plus [verschil] (de leider loopt zoveel voor), gemeld met [ruis].
    SamenAnker anker(int i, {int ruis = 0, int verschil = 0, String id = 'x'}) {
      final pc = KlokIjk().nuPcMs() + i;
      return SamenAnker(
          groep: 'spk:kef', trackId: id, rij: [id], index: 0, positieMs: 60000 + verschil + ruis + i, pcMs: pc, speelt: true);
    }

    test('DE KERN: de echte ruis van de KEF — de Shield staat gelijk en blijft vrijwel op 1,000', () {
      fakeAsync((fa) {
        final s = _Speler(t);
        final v = volger(s, fa);
        for (var i = 0; i < _kefRuis.length; i++) {
          v.opAnker(anker(i, ruis: _kefRuis[i]));
          fa.elapse(const Duration(seconds: 1));
        }
        expect(v.ruisMs, greaterThan(15), reason: 'de volger ziet zelf dat deze leider ruist');
        // De eerste twee tellen (één anker, de ruis nog onbekend) telt niet: in het echt kent de volger de ruis dan al van
        // het vorige nummer — die schatting blijft over nummers heen.
        final daarna = s.snelheden.skip(2).toList();
        expect(daarna.where((x) => (x - 1).abs() > 0.004), isEmpty,
            reason: 'voorheen sprong hij hier keer op keer naar 0,990 en 1,010');
        // Sinds 3.9.769 krijgt de speler alleen een opdracht als de snelheid echt verandert, in stappen van 0,25 % en
        // hoogstens eens per 5 s (elke opdracht kan een tikje geven): in 26 s hooguit een paar.
        expect(s.snelheden.length, lessThanOrEqualTo(4));
        expect(s.seeks, isEmpty);
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('een echt verschil (de leider loopt 80 ms voor) werkt hij wel weg, zacht', () {
      fakeAsync((fa) {
        final s = _Speler(t);
        final v = volger(s, fa);
        for (var i = 0; i < 8; i++) {
          v.opAnker(anker(i, verschil: 80, ruis: i.isEven ? 4 : -4));
          fa.elapse(const Duration(seconds: 1));
        }
        expect(s.snelheden.last, inInclusiveRange(1.006, 1.01), reason: 'de Shield loopt achter: iets sneller');
        expect(s.seeks, isEmpty);
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('een precieze leider (een Sonos): vanaf 20 ms, zacht, zoals voorheen maar zonder sprong naar 1 %', () {
      fakeAsync((fa) {
        final s = _Speler(t);
        final v = volger(s, fa);
        for (var i = 0; i < 6; i++) {
          v.opAnker(anker(i, verschil: -30, ruis: i.isEven ? 1 : -1));
          fa.elapse(const Duration(seconds: 1));
        }
        expect(v.ruisMs, lessThan(5));
        expect(s.snelheden.last, inInclusiveRange(0.996, 0.998), reason: '30 ms voor: 0,3 % trager');
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('stappen van 0,25 %, en een gezette snelheid blijft minstens 5 s staan (elke opdracht kan een tikje geven)', () {
      expect(snelheidsstap(0.9902), 0.99);
      expect(snelheidsstap(1.0012), 1.0);
      expect(snelheidsstap(0.9963), 0.9975);
      expect(snelheidsstap(1.0038), 1.005);
      fakeAsync((fa) {
        final s = _Speler(t);
        final v = volger(s, fa);
        for (var i = 0; i < 3; i++) {
          v.opAnker(anker(i, verschil: 60, ruis: i.isEven ? 1 : -1));
        }
        fa.elapse(const Duration(milliseconds: 600));
        expect(s.snelheden, [1.005], reason: '60 ms achter: 0,6 % sneller, afgerond 0,5 %');
        // Meteen daarna staat hij 60 ms vóór: binnen 5 s niet omgooien.
        for (var i = 3; i < 9; i++) {
          v.opAnker(anker(i, verschil: -60, ruis: i.isEven ? 1 : -1));
        }
        fa.elapse(const Duration(seconds: 3));
        expect(s.snelheden, [1.005], reason: 'vasthouden');
        fa.elapse(const Duration(seconds: 3));
        expect(s.snelheden, [1.005, 0.995], reason: 'na 5 s mag hij');
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('na een pauze van de leider, of een onzekere meting, weet de volger dat de speler weer op 1,000 staat', () {
      fakeAsync((fa) {
        final s = _Speler(t);
        final v = volger(s, fa);
        for (var i = 0; i < 3; i++) {
          v.opAnker(anker(i, verschil: 60, ruis: i.isEven ? 1 : -1));
        }
        fa.elapse(const Duration(milliseconds: 600));
        expect(s.snelheden.last, 1.005);
        final pc = KlokIjk().nuPcMs();
        // De leider pauzeert en speelt weer, nog steeds 60 ms voor: de volger zet opnieuw 1,005 (hij weet dat de speler op
        // 1,000 staat).
        v.opAnker(SamenAnker(
            groep: 'spk:kef', trackId: 'x', rij: const ['x'], index: 0, positieMs: 60060, pcMs: pc + 60, speelt: false));
        fa.elapse(const Duration(seconds: 6));
        expect(s.snelheden.last, 1.0);
        s.playing = true;
        for (var i = 70; i < 73; i++) {
          v.opAnker(anker(i, verschil: 60, ruis: i.isEven ? 1 : -1));
        }
        fa.elapse(const Duration(milliseconds: 600));
        expect(s.snelheden.last, 1.005, reason: 'na de pauze opnieuw gezet');
        // Een meting die de pc zelf niet vertrouwt: terug naar 1,000.
        fa.elapse(const Duration(seconds: 6));
        v.opAnker(SamenAnker(
            groep: 'spk:kef', trackId: 'x', rij: const ['x'], index: 0, positieMs: 60060, pcMs: pc + 90, speelt: true,
            onzekerMs: 200));
        fa.elapse(const Duration(milliseconds: 600));
        expect(s.snelheden.last, 1.0);
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('de mediaan begint opnieuw bij een ander nummer, en bij een sprong van de leider', () {
      fakeAsync((fa) {
        final s = _Speler(t);
        final v = volger(s, fa);
        for (var i = 0; i < 4; i++) {
          v.opAnker(anker(i));
        }
        expect(v.leiderStart, isNotNull);
        // De leider spoelt twee seconden verder: de oude ankers gelden niet meer.
        v.opAnker(anker(5, verschil: 2000));
        expect(v.leiderStart, isNull, reason: 'nog maar één anker na de sprong');
        v.opAnker(anker(6, verschil: 2000));
        v.opAnker(anker(7, verschil: 2000));
        expect(v.leiderStart, isNotNull);
        // Een ander nummer op dezelfde tijdlijn (geen sprong): toch opnieuw.
        v.opAnker(anker(8, id: 'y', verschil: 2000));
        expect(v.leiderStart, isNull, reason: 'een ander nummer');
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('alleen de laatste vijf ankers: schuift de leider langzaam (minder dan een seconde), dan schuift de mediaan mee',
        () {
      fakeAsync((fa) {
        final s = _Speler(t);
        final v = volger(s, fa);
        for (var i = 0; i < 8; i++) {
          v.opAnker(anker(i));
        }
        final eerst = v.leiderStart!;
        for (var i = 8; i < 13; i++) {
          v.opAnker(anker(i, verschil: 300));
        }
        expect(eerst - v.leiderStart!, inInclusiveRange(295, 310), reason: 'de laatste vijf staan 300 ms verder');
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('een klein echt verschil onder de ruis van de leider: niet bijsturen', () {
      fakeAsync((fa) {
        final s = _Speler(t);
        final v = volger(s, fa);
        // Ruis die de mediaan opheft (0, +60, −60, …), rond een echt verschil van 30 ms.
        const patroon = [0, 60, -60];
        for (var i = 0; i < 12; i++) {
          v.opAnker(anker(i, verschil: -30, ruis: patroon[i % 3]));
          fa.elapse(const Duration(seconds: 1));
        }
        expect(v.ruisMs, greaterThan(40));
        expect(s.snelheden.skip(4).where((x) => x != 1.0), isEmpty, reason: '30 ms valt binnen de ruis van deze leider');
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('de ruis telt geen sprong van de leider, en geen anker dat twee keer kwam', () {
      fakeAsync((fa) {
        final s = _Speler(t);
        final v = volger(s, fa);
        for (var i = 0; i < 5; i++) {
          v.opAnker(anker(i));
        }
        v.opAnker(anker(5, verschil: 2000));
        expect(v.ruisMs, lessThan(5), reason: 'een sprong van twee seconden is geen ruis');
        final w = volger(_Speler(t), fa);
        const patroon = [0, 60, -60];
        for (var i = 0; i < 12; i++) {
          final a = anker(i, ruis: patroon[i % 3]);
          w
            ..opAnker(a)
            ..opAnker(a);
        }
        expect(w.ruisMs, greaterThan(50), reason: 'hetzelfde anker nog eens is geen nieuwe meting (dan 0 erbij)');
        v.stop(pauzeer: false);
        w.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });
  });
}
