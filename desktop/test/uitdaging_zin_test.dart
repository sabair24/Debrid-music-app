/// Wat het scherm zegt als Cloudflare de app tegenhoudt — en of dat advies klopt.
///
/// **Waarom dit bestaat.** De app heeft een verborgen browservenster dat juist gebouwd is om die
/// uitdaging op te lossen. Slaagt dát niet, dan is "meld je opnieuw aan" het verkeerde advies: je
/// krijgt een vers koekje en loopt tegen dezelfde muur.
///
/// Gemeld op 26-08-2026, met een schermafdruk erbij: *"ik ben ingelogd bij rutracker"* — en
/// eronder stond de zin die zei dat hij zich opnieuw moest aanmelden. Hij had gelijk. De app had de
/// echte reden in handen (`haalReden`: het venster stond nog op te starten, of was er niet) en
/// gooide hem weg op precies de twee plekken waar hij nodig was.
///
/// Dit is de reden dat het advies zuiver en apart staat: zonder toestel en zonder RuTracker valt
/// alleen hier na te meten dat het bij de oorzaak past.
library;

import 'package:debridmusic/rutracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DE KERN: het advies past bij de oorzaak', () {
    test('ligt het aan het venster, dan is opnieuw aanmelden juist NIET het advies', () {
      final zin = RuTrackerService.uitdagingZin(
          'het browservenster is nog aan het opstarten — probeer over een paar tellen opnieuw');
      expect(zin, contains('Opnieuw aanmelden helpt hier niet'));
      expect(zin, contains('nog aan het opstarten'));
      expect(zin.contains('Instellingen → RuTracker → Aanmelden'), isFalse,
          reason: 'dat sturen we hem juist niet als het venster het probleem is');
    });

    test('een toestel zonder venster krijgt datzelfde eerlijke antwoord', () {
      final zin = RuTrackerService.uitdagingZin('dit toestel heeft geen ingebouwd browservenster');
      expect(zin, contains('Opnieuw aanmelden helpt hier niet'));
      expect(zin, contains('geen ingebouwd browservenster'));
    });

    test('kon het venster niet opgebouwd worden, dan staat dat er', () {
      final zin = RuTrackerService.uitdagingZin('het browservenster kon niet opgebouwd worden');
      expect(zin, contains('Opnieuw aanmelden helpt hier niet'));
    });
  });

  group('als het NIET aan het venster ligt', () {
    test('geen reden: dan gewoon de gewone uitleg', () {
      expect(RuTrackerService.uitdagingZin(''), RuTrackerService.uitdagingUitleg);
      expect(RuTrackerService.uitdagingZin('   '), RuTrackerService.uitdagingUitleg);
    });

    test('een andere reden gaat mee ACHTER het advies, niet in plaats ervan', () {
      // Hier is opnieuw aanmelden wél de goede weg — het venster deed zijn werk en kwam met een
      // uitdaging terug. Maar de reden hoort er nog steeds bij: zonder die zin is er de volgende
      // keer weer niets om op te varen.
      final zin = RuTrackerService.uitdagingZin('de gewone verbinding gaf: TimeoutException');
      expect(zin, startsWith(RuTrackerService.uitdagingUitleg));
      expect(zin, contains('TimeoutException'));
    });
  });

  group('de zin zelf', () {
    test('zegt altijd dat het niet aan je wachtwoord ligt of waar het wél aan ligt', () {
      // De hele reden dat deze zin bestaat: een 403 kwam er eerst uit als "controleer je gegevens",
      // en dan ga je je wachtwoord zitten nakijken terwijl de app RuTracker nooit gesproken heeft.
      for (final reden in [
        '',
        'het browservenster gaf niets terug',
        'dit toestel heeft geen ingebouwd browservenster',
        'de gewone verbinding gaf: SocketException',
      ]) {
        final zin = RuTrackerService.uitdagingZin(reden);
        expect(zin, contains('Cloudflare'));
        expect(zin.trim(), isNotEmpty);
        expect(zin, endsWith('.'), reason: 'een halve zin op het scherm leest als een fout');
      }
    });
  });
}
