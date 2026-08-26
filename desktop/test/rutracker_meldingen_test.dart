/// Dat de reden van een lege lijst óók echt op het scherm kan komen.
///
/// **Waarom hier een toets op staat, en waarom juist deze.** Er zijn een stuk of zes meldingen
/// bijgebouwd om nooit meer een woordloze lege lijst te tonen: geen aanmelding, sessie verlopen,
/// Cloudflare, een pagina zonder rijen, geen infohash. Op het scherm bleef er "Geen torrents
/// gevonden." staan, punt — precies zoals daarvoor.
///
/// De oorzaak zat niet in één van die meldingen maar in de bedrading eronder. `OnlineService`
/// maakte **twee** `RuTrackerService`-objecten: één als veld, en één in de zoekverdeler. Het zoeken
/// liep over het tweede en zette `lastError` daar; het scherm las `lastError` van het eerste. Alles
/// wat de app wist stond in een object dat niemand bekeek.
///
/// Dat het zoeken zélf wél werkte kwam doordat beide objecten hetzelfde `settings` lezen. Zo'n fout
/// heeft geen symptoom behalve stilte, en dat is precies waarom hij hier vastligt.
library;

import 'package:debridmusic/online.dart';
import 'package:debridmusic/rutracker.dart';
import 'package:debridmusic/search.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

RuTrackerService? uitDeVerdeler(OnlineService online) {
  for (final bron in online.aggregator.sources) {
    if (bron is RuTrackerSource) return bron.service;
  }
  return null;
}

void main() {
  group('DE KERN: het scherm en het zoeken kijken naar hetzelfde object', () {
    test('de RuTracker in de zoekverdeler is DEZELFDE als die van het veld', () {
      final online = OnlineService(AppSettings());
      expect(uitDeVerdeler(online), isNotNull, reason: 'RuTracker hoort in de verdeler te zitten');
      expect(identical(uitDeVerdeler(online), online.rutracker), isTrue,
          reason: 'twee objecten betekent dat geen enkele melding het scherm haalt');
    });

    test('een melding die het zoeken zet, is de melding die het scherm leest', () {
      // Dit is de bedrading nagespeeld: het zoeken schrijft op het object uit de verdeler, het
      // scherm leest van het veld. Met twee objecten blijft de tweede regel leeg.
      final online = OnlineService(AppSettings());
      uitDeVerdeler(online)!.lastError = 'de sessie is verlopen';
      expect(online.rutracker.lastError, 'de sessie is verlopen');
    });
  });

  group('zonder aanmelding wordt er niet gezwegen', () {
    test('geen koekje geeft een zin, geen lege lijst zonder uitleg', () async {
      final settings = AppSettings();
      final rt = RuTrackerService(settings);
      expect(await rt.search('pink i am not dead'), isEmpty);
      expect(rt.lastError, isNotEmpty);
      expect(rt.lastError.toLowerCase(), contains('aanmeld'));
    });

    test('het koekje ÍS de aanmelding — een wachtwoord is er niet voor nodig', () {
      // Wie zich in het browservenster aanmeldt vult nooit een naam en wachtwoord in. Vroeg dit om
      // die twee, dan stond er een geldig koekje klaar terwijl het zoeken meteen niets teruggaf.
      final settings = AppSettings();
      final rt = RuTrackerService(settings);
      expect(rt.configured, isFalse);
      settings.rutrackerCookie = 'bb_session=iets';
      expect(rt.configured, isTrue);
      expect(rt.kanZelfAanmelden, isFalse, reason: 'zelf inloggen vraagt wél om naam en wachtwoord');
    });
  });

  group('de zin bij een Cloudflare-uitdaging wijst naar het venster', () {
    test('niet meer naar de plakweg', () {
      // Het venster ís een echte browser en lost de uitdaging op; een geplakt koekje uit een andere
      // browser op een ander IP-adres doet dat niet. Naar de oude weg verwijzen stuurt je dus de
      // verkeerde kant op.
      expect(RuTrackerService.uitdagingUitleg, contains('Aanmelden'));
      expect(RuTrackerService.uitdagingUitleg.toLowerCase(), contains('echte browser'));
    });
  });
}
