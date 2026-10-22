/// Samen spelen: de volger neemt een gewijzigde wachtrij van de leider over (22-10-2026). Zette je in een
/// groep iets "hierna" op de leider, dan wist de volger dat pas bij de volgende wissel: hij speelde 1–2 s
/// zijn oude volgende nummer, tot het anker van de leider hem naar het goede liet springen.
///
/// Wat hier vastligt: de rij overnemen rond het nummer dat al klinkt (zonder het opnieuw te openen); niets
/// doen als de rij dezelfde is; niets als op die plek een ander nummer staat (dan opent de volger dat).
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/samen.dart';

Track _t(String id) => Track(path: '/m/$id.flac', title: id, artist: 'A', album: 'B');

/// Een speler die alleen bijhoudt wat de volger vraagt.
class _NepSpeler implements VolgSpeler {
  List<Track> rij = [];
  int index = 0;
  @override
  bool playing = false;
  final log = <String>[];

  @override
  Track? get current => index < rij.length ? rij[index] : null;
  @override
  Duration get positieNauwkeurig => const Duration(seconds: 30);
  @override
  List<Track> get queueTracks => List.unmodifiable(rij);
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
      {bool spelen = true, bool shuffle = false, RepeatMode herhaal = RepeatMode.off}) async {
    log.add('neemOver ${r.map((t) => t.title).join(',')} @$i');
    rij = List.of(r);
    index = i;
  }

  @override
  bool zetRijRondHuidig(List<Track> r, int i) {
    final w = rijRondHuidig(current, r, i);
    if (w == null) {
      log.add('zetRij geweigerd');
      return false;
    }
    log.add('zetRij ${r.map((t) => t.title).join(',')} @$i');
    rij = w.volgorde;
    index = w.index;
    return true;
  }
}

void main() {
  test('rijRondHuidig: alleen als op die plek het nummer staat dat nu klinkt', () {
    final a = _t('a'), b = _t('b'), x = _t('x');
    final w = rijRondHuidig(a, [a, x, b], 0)!;
    expect([for (final t in w.volgorde) t.title], ['a', 'x', 'b']);
    expect([for (final t in w.origineel) t.title], ['a', 'x', 'b']);
    expect(w.index, 0);
    expect(rijRondHuidig(a, [x, a, b], 1)!.index, 1);
    expect(rijRondHuidig(a, [x, a, b], 0), isNull, reason: 'op plek 0 staat een ander nummer');
    expect(rijRondHuidig(null, [a], 0), isNull);
    expect(rijRondHuidig(a, [a], 3), isNull);
  });

  test('de volger neemt een gewijzigde rij over rond het lopende nummer, en opent niets opnieuw', () {
    fakeAsync((fa) {
      final nummers = {for (final id in ['a', 'b', 'c', 'x', 'y']) id: _t(id)};
      final speler = _NepSpeler();
      final regels = <String>[];
      final volger = SamenVolger(
        speler: speler,
        nummer: (id) => nummers[id],
        idVan: (t) => t.title,
        klok: KlokIjk(),
        vertragingMs: () => 0,
        log: regels.add,
      );
      var pcMs = 1000000;
      SamenAnker anker(List<String> rij, int index) => SamenAnker(
          groep: 'spk:move', trackId: rij[index], rij: rij, index: index, positieMs: 30000, pcMs: pcMs, speelt: true);

      // Het eerste anker: openen.
      volger.opAnker(anker(['a', 'b', 'c'], 0));
      fa.elapse(const Duration(seconds: 2));
      expect(speler.log, ['neemOver a,b,c @0']);
      speler.playing = true;

      // De leider kreeg "x" hierna: overnemen, niet opnieuw openen.
      speler.log.clear();
      pcMs += 2000;
      volger.opAnker(anker(['a', 'x', 'b', 'c'], 0));
      fa.flushMicrotasks();
      expect(speler.log, ['zetRij a,x,b,c @0']);
      expect(regels.last, contains('wachtrij van de leider overgenomen (4 nummers)'));

      // Dezelfde rij nog eens: niets.
      speler.log.clear();
      volger.opAnker(anker(['a', 'x', 'b', 'c'], 0));
      fa.flushMicrotasks();
      expect(speler.log, isEmpty);

      // Een nummer dat hier niet staat, valt weg; de plek schuift mee.
      volger.opAnker(anker(['y', 'a', 'zz', 'c'], 1));
      fa.flushMicrotasks();
      expect(speler.log, ['zetRij y,a,c @1']);

      volger.stop(pauzeer: false);
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });
}
