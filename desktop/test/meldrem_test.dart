/// De rem op de voortgangsmeldingen van de downloads.
///
/// **Waarom dit bestaat.** `DownloadManager` is één app-brede melder en op een telefoon hangt de
/// hele schil eraan. Elke gebeurtenis van elke lopende download meldde meteen: de eerste bytes, elke
/// twee procent per bestand, elke peer die antwoordt. Dat markeert bij een paar downloads tegelijk
/// meerdere keren per seconde de hele schil vuil.
///
/// Dit is precies het soort code dat STIL kapotgaat, en daarom staat het apart en wordt het getoetst
/// (zie `werkrij.dart`, waar dezelfde afweging staat):
///
/// * een vlag die blijft staan → er wordt nooit meer iets gemeld, zonder foutmelding: downloads die
///   op nul procent blijven staan terwijl ze gewoon binnenkomen;
/// * een tijdklok die afgaat nádat er opgeruimd is → `notifyListeners()` na `dispose()`, en dat
///   gooit in Flutter;
/// * een eindtoestand die meegeremd wordt → "Klaar" verschijnt te laat, of erger: helemaal niet
///   omdat er daarna niets meer gebeurt dat een melding uitlokt.
library;

import 'package:debridmusic/meldrem.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DE KERN: veel vragen, weinig melden', () {
    test('honderd vragen binnen één tussenpoos geven één melding', () {
      fakeAsync((async) {
        var n = 0;
        final rem = Meldrem(() => n++, tussenpoos: const Duration(milliseconds: 200));
        for (var i = 0; i < 100; i++) {
          rem.vraag();
        }
        expect(n, 0, reason: 'nog niets: de eerste melding wacht op de klok');
        async.elapse(const Duration(milliseconds: 250));
        expect(n, 1);
      });
    });

    test('een lange stroom levert vijf meldingen per seconde', () {
      fakeAsync((async) {
        var n = 0;
        final rem = Meldrem(() => n++, tussenpoos: const Duration(milliseconds: 200));
        // Zoals een download het doet: veel vaker vragen dan er gemeld mag worden.
        for (var i = 0; i < 100; i++) {
          rem.vraag();
          async.elapse(const Duration(milliseconds: 10));
        }
        expect(n, 5, reason: 'één seconde aan gebeurtenissen → vijf meldingen');
      });
    });

    test('DE KERN: na een melding kan er weer gevraagd worden', () {
      // Dit is de faalvorm die niets zegt: een vlag die blijft staan, en de app meldt nooit meer.
      fakeAsync((async) {
        var n = 0;
        final rem = Meldrem(() => n++, tussenpoos: const Duration(milliseconds: 200));
        rem.vraag();
        async.elapse(const Duration(milliseconds: 250));
        expect(n, 1);
        rem.vraag();
        async.elapse(const Duration(milliseconds: 250));
        expect(n, 2);
        expect(rem.wacht, isFalse);
      });
    });

    test('niets vragen meldt niets', () {
      fakeAsync((async) {
        var n = 0;
        Meldrem(() => n++);
        async.elapse(const Duration(seconds: 5));
        expect(n, 0);
      });
    });
  });

  group('DE KERN: een eindtoestand wacht nergens op', () {
    test('nu() meldt meteen', () {
      fakeAsync((async) {
        var n = 0;
        final rem = Meldrem(() => n++, tussenpoos: const Duration(milliseconds: 200));
        rem.nu();
        expect(n, 1, reason: '"Klaar" hoort niet 200 ms achter te lopen');
      });
    });

    test('nu() laat een wachtende melding vervallen in plaats van hem te verdubbelen', () {
      fakeAsync((async) {
        var n = 0;
        final rem = Meldrem(() => n++, tussenpoos: const Duration(milliseconds: 200));
        rem.vraag();
        rem.nu();
        expect(n, 1);
        async.elapse(const Duration(seconds: 1));
        expect(n, 1, reason: 'de geplande melding voegde niets meer toe');
      });
    });
  });

  group('DE KERN: opruimen', () {
    test('een klok die na stop() afgaat meldt niet meer', () {
      // Zonder deze bewaking roept de klok `notifyListeners()` aan op een ChangeNotifier die al
      // opgeruimd is, en dat gooit. Precies het soort fout dat pas bij het afsluiten opduikt.
      fakeAsync((async) {
        var n = 0;
        final rem = Meldrem(() => n++, tussenpoos: const Duration(milliseconds: 200));
        rem.vraag();
        rem.stop();
        async.elapse(const Duration(seconds: 1));
        expect(n, 0);
      });
    });

    test('na stop() doet vragen en meteen melden allebei niets', () {
      fakeAsync((async) {
        var n = 0;
        final rem = Meldrem(() => n++);
        rem.stop();
        rem.vraag();
        rem.nu();
        async.elapse(const Duration(seconds: 1));
        expect(n, 0);
      });
    });

    test('twee keer stoppen mag', () {
      final rem = Meldrem(() {});
      rem.stop();
      rem.stop();
      expect(rem.wacht, isFalse);
    });
  });
}
