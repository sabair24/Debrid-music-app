/// Twee klokken die te snel liepen.
///
/// Allebei hetzelfde patroon: een vast interval van twee seconden dat iets duurs deed, ongeacht of
/// er iets te doen viel. En allebei op de plek waar het het meeste kost — de tekendraad van een
/// telefoon, en zijn accu.
///
///   1. **De feitenindex.** Elke binnengekomen tracklist zette een klok van twee seconden, en die
///      schreef de HELE index opnieuw weg: van elk album de feiten naar een kaart, dan `jsonEncode`
///      over het geheel. Bij een grote bibliotheek bijna tien megabyte, om er één album aan toe te
///      voegen. `jsonEncode` is gewone Dart-code en draait dus op de tekendraad.
///   2. **De downloadpeiling.** Boven `startWatching` stond al jaren dat er trager gepeild moest
///      worden als er niets liep — en eronder stond een `Timer.periodic` van twee seconden zonder
///      meer. Dertig verzoeken per minuut naar de pc, de hele dag, voor een lijst die meestal leeg
///      is.
///
/// Zuiver: een getal in, een duur uit. Geen klok, geen netwerk, geen schijf — dus na te meten
/// zonder toestel.
library;

import 'package:debridmusic/album_facts.dart';
import 'package:debridmusic/lan/remote_services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DE FEITENINDEX: wachten in verhouding tot wat schrijven kost', () {
    test('kost schrijven niets, dan verandert er niets aan vroeger', () {
      // De bodem. Wie een kleine bibliotheek heeft merkt van deze hele wijziging niets, en dat is
      // de bedoeling: daar was twee seconden nooit een probleem.
      expect(wachtVoorIndex(Duration.zero), const Duration(seconds: 2));
      expect(wachtVoorIndex(const Duration(milliseconds: 10)), const Duration(seconds: 2));
      expect(wachtVoorIndex(const Duration(milliseconds: 99)), const Duration(seconds: 2));
    });

    test('kost schrijven een kwart seconde, dan wordt het vijf', () {
      // De regel: hooguit een twintigste van de tijd aan deze boekhouding. 250 ms × 20 = 5 s.
      expect(wachtVoorIndex(const Duration(milliseconds: 250)), const Duration(seconds: 5));
    });

    test('een trage schijf duwt hem verder op, tot het plafond', () {
      expect(wachtVoorIndex(const Duration(seconds: 1)), const Duration(seconds: 20));
      expect(wachtVoorIndex(const Duration(seconds: 3)), const Duration(seconds: 60));
      // Zonder plafond zou een schijf die even hangt betekenen dat je een kwartier op je index
      // wacht. Er is niets verloren zolang je wacht, maar wachten is ook geen doel.
      expect(wachtVoorIndex(const Duration(minutes: 5)), const Duration(seconds: 60));
    });

    test('de klok loopt nooit terug als schrijven duurder wordt', () {
      // De eigenschap waar het om gaat: hoe groter de bibliotheek, hoe rustiger deze boekhouding.
      // Nooit andersom.
      var vorige = Duration.zero;
      for (var ms = 0; ms <= 4000; ms += 50) {
        final nu = wachtVoorIndex(Duration(milliseconds: ms));
        expect(nu >= vorige, isTrue, reason: 'bij $ms ms werd de wachttijd korter');
        vorige = nu;
      }
    });

    test('bodem en plafond zijn zelf in te stellen, en houden zich aan elkaar', () {
      expect(
          wachtVoorIndex(Duration.zero,
              bodem: const Duration(seconds: 1), plafond: const Duration(seconds: 5)),
          const Duration(seconds: 1));
      expect(
          wachtVoorIndex(const Duration(seconds: 10),
              bodem: const Duration(seconds: 1), plafond: const Duration(seconds: 5)),
          const Duration(seconds: 5));
    });
  });

  group('DE PEILING: trager worden als er niets gebeurt', () {
    test('zolang er iets loopt blijft het twee seconden', () {
      // De teller staat op nul zodra er een lopende taak in de lijst staat.
      expect(peilTempo(0), const Duration(seconds: 2));
    });

    test('de eerste rondes na een download blijven snel', () {
      // Juist dan kan er nog iets komen: een nummer dat nakomt, een fout die binnenvalt.
      for (final n in [1, 2, 3]) {
        expect(peilTempo(n), const Duration(seconds: 2), reason: 'ronde $n');
      }
    });

    test('daarna zakt hij terug, in stappen', () {
      expect(peilTempo(4), const Duration(seconds: 5));
      expect(peilTempo(8), const Duration(seconds: 5));
      expect(peilTempo(9), const Duration(seconds: 15));
      expect(peilTempo(20), const Duration(seconds: 15));
      expect(peilTempo(21), const Duration(seconds: 30));
    });

    test('en blijft daar staan, hoe lang het ook stil is', () {
      // Geen oneindig oplopende ladder: een app die een uur openstaat moet nog steeds binnen een
      // halve minuut merken dat de pc iets is gaan doen.
      expect(peilTempo(1000), const Duration(seconds: 30));
      expect(peilTempo(100000), const Duration(seconds: 30));
    });

    test('de ladder loopt nooit terug', () {
      var vorige = Duration.zero;
      for (var n = 0; n <= 60; n++) {
        final nu = peilTempo(n);
        expect(nu >= vorige, isTrue, reason: 'bij $n rondes werd er weer sneller gepeild');
        vorige = nu;
      }
    });

    test('een stille dag kost geen dertig verzoeken per minuut meer', () {
      // Waar het om begonnen was, in één som: een uur met de app open en niets aan de hand.
      var seconden = 0.0, verzoeken = 0, stilte = 0;
      while (seconden < 3600) {
        seconden += peilTempo(stilte).inMilliseconds / 1000;
        stilte++;
        verzoeken++;
      }
      expect(verzoeken, lessThan(200), reason: 'was 1800 met een vaste klok van twee seconden');
    });
  });
}
