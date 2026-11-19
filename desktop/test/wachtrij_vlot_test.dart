/// Een vlotte wachtrij (19-11-2026), stap 1 vóór de manuele radio en slim shuffelen.
///
/// Saber: *"houdt rekening met performance, alles moet vlot gaan"*. Gevonden bij Shuffle alles (2000 nummers):
/// het wachtrijpaneel luisterde naar elke melding van de speler, dus ook naar de vier positietikken per seconde,
/// en kopieerde daarbij telkens de hele rij en maakte 2000 sleutels; en elke wijziging van de rij schreef het hele
/// `resume_queue.json` (226 kB) opnieuw weg.
library;

import 'dart:io';

import 'package:debridmusic/naklok.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('Naklok: hoogstens één keer per rust', () {
    test('DE KERN: tien wijzigingen kort na elkaar geven één keer wegschrijven, met de stand van het einde', () {
      fakeAsync((t) {
        var keer = 0;
        var stand = 0;
        var weg = -1;
        final k = Naklok(const Duration(seconds: 2), () async {
          keer++;
          weg = stand;
        });
        for (var i = 1; i <= 10; i++) {
          stand = i;
          k.straks();
          t.elapse(const Duration(milliseconds: 100));
        }
        expect(keer, 0, reason: 'nog binnen de rust');
        t.elapse(const Duration(seconds: 2));
        expect(keer, 1);
        expect(weg, 10, reason: 'de stand van het moment dat de klok afgaat');
        expect(k.wacht, isFalse);
      });
    });

    test('DE GRENS: een gestage stroom wijzigingen schuift het wegschrijven niet eindeloos op', () {
      fakeAsync((t) {
        var keer = 0;
        final k = Naklok(const Duration(seconds: 2), () async => keer++);
        for (var i = 0; i < 60; i++) {
          k.straks();
          t.elapse(const Duration(milliseconds: 500));
        }
        expect(keer, greaterThanOrEqualTo(14), reason: 'elke twee seconden, ook als er steeds iets bijkomt');
        expect(keer, lessThanOrEqualTo(16));
      });
    });

    test('nu: meteen, en de wachtende beurt vervalt; stop: niets', () {
      fakeAsync((t) {
        var keer = 0;
        final k = Naklok(const Duration(seconds: 2), () async => keer++);
        k.straks();
        k.nu();
        t.flushMicrotasks();
        expect(keer, 1);
        t.elapse(const Duration(seconds: 3));
        expect(keer, 1, reason: 'de klok van daarnet is weg');
        k.straks();
        k.stop();
        t.elapse(const Duration(seconds: 3));
        expect(keer, 1);
      });
    });
  });

  group('aangesloten', () {
    test('de positietik telt niet als nieuwe stand, al het andere wel', () {
      final p = _bron('lib/player.dart');
      expect(p, contains('    if (!_positieTik) _staatVersie++;\n    traagMeten(\'speler meldt\', super.notifyListeners);'));
      expect(p, contains('      if (vak == _laatsteMeldvak) return;\n      _laatsteMeldvak = vak;\n      _meldPositie();'),
          reason: 'de tijdbalk meldt zonder de stand te verhogen');
    });

    test('het wachtrijpaneel hertekent op de stand, niet op elke melding', () {
      final m = _bron('lib/main.dart');
      expect(m, contains('    context.select<PlayerStore, int>((p) => p.staatVersie);\n    final lokaal = context.read<PlayerStore>();'));
      expect(m.contains('    // De wachtrij van de gekozen zone (zones, 21-10-2026), of die van dit toestel.\n    final lokaal = context.watch<PlayerStore>();'),
          isFalse);
    });

    test('queueTracks is een venster op de rij, geen kopie', () {
      final p = _bron('lib/player.dart');
      expect(p.contains('List<Track> get queueTracks => List.unmodifiable(_order);'), isFalse);
      expect(p, contains('      _rijZicht = UnmodifiableListView(o);'));
    });

    test('een wijziging schrijft de rij straks weg, en het afsluiten meteen', () {
      final p = _bron('lib/player.dart');
      expect(p, contains('  void _naWijziging() {\n    _rijBewaren.straks();'));
      expect(p, contains('late final Naklok _rijBewaren = Naklok(kRijBewaarRust, _saveQueue);'));
      final m = _bron('lib/main.dart');
      expect(m, contains('    await PlayerStore.laatst?.bewaarRijNu();'));
    });
  });
}
