library;

import 'package:debridmusic/player.dart';
import 'package:flutter_test/flutter_test.dart';

/// **GETELD OP 14-09-2026, over 23 dagen `speler.log` van de telefoon.**
///
/// De klacht was "de bluetooth-buds haperen". Het logboek zegt iets anders: 131 keer OPENEN
/// MISLUKT, bijna zes keer per dag, en de helft daarvan met de buds niet eens in. Wat je hoort is
/// geen bluetooth maar een nummer dat niet opengaat en pas na de herkansing begint.
///
/// Vier tellen stond er voor iedereen, en dat kwam uit een goede waarneming: een pc die een hi-res
/// bestand eerst helemaal omzet stuurt tien tot twintig seconden lang geen byte. Wie dan te snel
/// opnieuw vraagt krijgt precies dezelfde fout, en de omgezette kopie staat er na vier tellen wel.
///
/// Maar dat geldt maar voor de helft van de gevallen:
///
///     60 van de 131 hadden `maxRate` in het adres  -> de pc stond te converteren
///     71 hadden dat niet                           -> er hoefde alleen verbonden te worden
///
/// En die tweede groep zit vooral vooraan: van de 69 mislukkingen binnen een minuut na het starten
/// van een luisterblok vroegen er 38 helemaal geen omzetting. Daar is vier seconden geen geduld
/// maar stilte om niets - een verse verbinding naar de pc kostte thuis gemeten 5 tot 17 ms, naar
/// zowel het lokale adres als dat van Tailscale.
///
/// Wat deze toets vasthoudt is dat onderscheid. Eén getal voor allebei is per definitie fout voor
/// een van de twee.
void main() {
  group('de tweede poging op een nummer dat niet openging', () {
    test('DE KERN: zonder omzetting hoor je een hikje, geen stilte', () {
      final kort = herkansingNa(pcMoestOmzetten: false);

      expect(kort.inMilliseconds, greaterThan(200),
          reason: 'onder de tweehonderd ms is het dezelfde mislukte verbinding, alleen sneller');
      expect(kort.inMilliseconds, lessThan(1000),
          reason: 'boven een seconde klinkt het als stilte en niet als een hapering');
    });

    test('DE VAL: mét omzetting blijft het vier tellen', () {
      // Hier NIET versnellen. De pc zet het bestand eerst helemaal om en stuurt in die tien tot
      // twintig seconden geen byte; wie na zevenhonderd milliseconden opnieuw vraagt krijgt
      // gegarandeerd dezelfde fout en verbrandt de enige herkansing die er is.
      expect(herkansingNa(pcMoestOmzetten: true), const Duration(seconds: 4));
    });

    test('DE GRENS: de twee zijn echt verschillend', () {
      expect(herkansingNa(pcMoestOmzetten: false),
          lessThan(herkansingNa(pcMoestOmzetten: true)),
          reason: 'een gedeeld getal is voor een van de twee gevallen altijd het verkeerde');
    });
  });
}
