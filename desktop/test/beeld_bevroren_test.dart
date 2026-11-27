/// De bewaker van het beeld: een app die doorloopt maar niets meer tekent.
///
/// **Waarom (27-11-2026).** Saber: "oei de app zit vast op de pc". Het scherm stond van 11:34:50 tot na 12:15 op
/// "Dancing On The Ceiling", terwijl de app eronder verzoeken in 4 ms beantwoordde en de muziek doorliep. warmte.log
/// zag 0 beelden/s met een tikker die wachtte, later een schuifovergang en drie aanrakingen — maar niets schreef op wát
/// er stilstond, en niets probeerde het los te maken.
library;

import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:debridmusic/warmtemeter.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Beeldstand _stand({bool aan = true, bool gepland = false, int tikkers = 0}) =>
    (aan: aan, gepland: gepland, tikkers: tikkers, tekst: 'proef tikkers $tikkers');

void main() {
  group('de bewaker van het beeld', () {
    late int nu;
    late Beeldstand stand;
    late List<String> regels;
    late int geforceerd;
    late int losgemaakt;

    Warmtemeter meter({bool metLosmaken = true}) => Warmtemeter(
          stuur: (_) async {},
          toestelstand: () async => null,
          bijBevroren: regels.add,
          losmaken: metLosmaken
              ? () async {
                  losgemaakt++;
                  return 'venster even van maat';
                }
              : null,
          beeldstand: () => stand,
          forceerBeeld: () => geforceerd++,
          nuMs: () => nu,
        );

    /// [ms] verder, met elke 100 ms een blik zoals de klok van de meter.
    void verder(Warmtemeter m, int ms) {
      for (var i = 0; i < ms ~/ 100; i++) {
        nu += 100;
        m.kijkBeeld();
      }
    }

    setUp(() {
      nu = 1000000;
      stand = _stand();
      regels = [];
      geforceerd = 0;
      losgemaakt = 0;
    });

    test('een tikker die 5 s geen beeld krijgt: opschrijven met de stand, en een beeld afdwingen', () {
      final m = meter()..beeldGezien();
      stand = _stand(tikkers: 1);
      verder(m, 4900);
      expect(regels, isEmpty);
      expect(geforceerd, 0);
      verder(m, 200);
      expect(regels, hasLength(1));
      expect(regels.single, startsWith('BEELD BEVROREN — 5.0 s geen beeld'));
      expect(regels.single, contains('proef tikkers 1'));
      expect(geforceerd, 1);
      expect(m.bevrorenStap, 1);
      verder(m, 2000);
      expect(geforceerd, 1, reason: 'één keer afdwingen, niet elke 100 ms');
    });

    test('nog altijd niets na nog eens 5 s: losmaken, en daarna hoogstens elke minuut', () {
      fakeAsync((fa) {
        final m = meter()..beeldGezien();
        stand = _stand(gepland: true);
        verder(m, 5100);
        expect(losgemaakt, 0);
        verder(m, 4800);
        fa.flushMicrotasks();
        expect(losgemaakt, 0, reason: 'eerst 5 s het gedwongen beeld een kans geven');
        verder(m, 200);
        fa.flushMicrotasks();
        expect(losgemaakt, 1);
        expect(regels.last, contains('losgemaakt (1): venster even van maat'));
        expect(m.bevrorenStap, 2);
        verder(m, 50000);
        fa.flushMicrotasks();
        expect(losgemaakt, 1);
        verder(m, 10100);
        fa.flushMicrotasks();
        expect(losgemaakt, 2);
      });
    });

    test('komt het beeld terug, dan staat dat erbij, met hoe lang en waardoor', () {
      fakeAsync((fa) {
        final m = meter()..beeldGezien();
        stand = _stand(tikkers: 2);
        verder(m, 5100);
        m.beeldGezien();
        expect(regels.last, 'BEELD WEER TERUG na 5.0 s (na een gedwongen beeld)');
        expect(m.bevrorenStap, 0);
        verder(m, 10100);
        fa.flushMicrotasks();
        m.beeldGezien();
        expect(regels.last, startsWith('BEELD WEER TERUG na 10.'));
        expect(regels.last, endsWith('(na 1× losmaken)'));
      });
    });

    test('niets gevraagd, of tekenen mag niet (geminimaliseerd): geen alarm, hoe lang het ook stil is', () {
      final m = meter()..beeldGezien();
      verder(m, 60000);
      stand = _stand(aan: false, tikkers: 3, gepland: true);
      verder(m, 60000);
      expect(regels, isEmpty);
      expect(geforceerd, 0);
    });

    test('een vraag na lange rust telt vanaf de vraag, niet vanaf het laatste beeld', () {
      final m = meter()..beeldGezien();
      verder(m, 60000);
      stand = _stand(tikkers: 1);
      verder(m, 3000);
      expect(regels, isEmpty, reason: 'het laatste beeld is een minuut oud, maar de vraag pas 3 s');
      verder(m, 2100);
      expect(regels, hasLength(1));
    });

    test('een vraag die ophoudt en later terugkomt, telt opnieuw vanaf de nieuwe vraag', () {
      final m = meter()..beeldGezien();
      stand = _stand(tikkers: 1);
      verder(m, 3000);
      stand = _stand();
      verder(m, 60000);
      stand = _stand(tikkers: 1);
      verder(m, 4800);
      expect(regels, isEmpty, reason: 'de oude vraag van een minuut geleden telt niet mee');
      verder(m, 300);
      expect(regels, hasLength(1));
    });

    test('aangesloten: de klok van 100 ms kijkt, en echte beeldtijden tellen als beeld', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      fakeAsync((fa) {
        final m = Warmtemeter(
          stuur: (_) async {},
          toestelstand: () async => null,
          bijBevroren: regels.add,
          beeldstand: () => stand,
          forceerBeeld: () => geforceerd++,
          nuMs: () => nu + fa.elapsed.inMilliseconds,
        )..start();
        stand = _stand(tikkers: 1);
        // Elke seconde een beeld, via de echte weg van de motor naar de beeldtijden.
        for (var i = 0; i < 8; i++) {
          fa.elapse(const Duration(seconds: 1));
          WidgetsBinding.instance.platformDispatcher.onReportTimings?.call([
            FrameTiming(
              vsyncStart: 0,
              buildStart: 1,
              buildFinish: 2,
              rasterStart: 3,
              rasterFinish: 4,
              rasterFinishWallTime: 4,
            ),
          ]);
        }
        expect(regels, isEmpty, reason: 'er kwamen beelden');
        fa.elapse(const Duration(milliseconds: 5200));
        expect(regels, hasLength(1), reason: 'de klok zag het zelf');
        m.stop();
      });
    });

    test('beelden die gewoon komen: nooit een alarm', () {
      final m = meter()..beeldGezien();
      stand = _stand(tikkers: 1);
      for (var i = 0; i < 300; i++) {
        verder(m, 1000);
        m.beeldGezien();
      }
      expect(regels, isEmpty);
    });

    test('zonder losmaken (een toestel zonder venster): alleen opschrijven en afdwingen', () {
      fakeAsync((fa) {
        final m = meter(metLosmaken: false)..beeldGezien();
        stand = _stand(tikkers: 1);
        verder(m, 30000);
        fa.flushMicrotasks();
        expect(regels, hasLength(1));
        expect(geforceerd, 1);
        expect(losgemaakt, 0);
      });
    });

    test('losmaken dat mislukt staat er ook', () {
      fakeAsync((fa) {
        final m = Warmtemeter(
          stuur: (_) async {},
          toestelstand: () async => null,
          bijBevroren: regels.add,
          losmaken: () => Future<String>.error(StateError('geen venster')),
          beeldstand: () => stand,
          forceerBeeld: () => geforceerd++,
          nuMs: () => nu,
        )..beeldGezien();
        stand = _stand(tikkers: 1);
        verder(m, 10200);
        fa.flushMicrotasks();
        expect(regels.last, contains('losmaken (1) mislukt'));
      });
    });

    test('de echte stand zegt wat er te zeggen valt', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final s = echteBeeldstand();
      expect(s.tekst, contains('tekenen'));
      expect(s.tekst, contains('beeld gevraagd'));
      expect(s.tekst, contains('tikkers'));
      expect(s.tekst, contains('vensters'));
    });
  });

  test('de app sluit de bewaker aan: op elk toestel opschrijven, op de pc ook losmaken', () {
    final bron = File('lib/main.dart').readAsStringSync();
    expect('bijBevroren: haperBevroren'.allMatches(bron), hasLength(2));
    expect(bron, contains('losmaken: vensterLosmaken,'));
    expect(bron, contains('losmaken: _isDesktop ? vensterLosmaken : null,'));
  });
}
