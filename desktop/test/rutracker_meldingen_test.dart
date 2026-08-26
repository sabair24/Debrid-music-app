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
import 'package:debridmusic/torbox.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een RuTracker die teruggeeft wat de toets nodig heeft, zonder net.
class _NepRt extends RuTrackerService {
  _NepRt(super.settings, this.uit);
  final List<SearchResult> uit;
  @override
  Future<List<SearchResult>> search(String query, {bool allowRelogin = true}) async => uit;
}

SearchResult _treffer(String naam) => SearchResult(
      name: naam,
      magnet: 'magnet:?xt=urn:btih:${'a' * 40}',
      hash: 'a' * 40,
      source: 'RuTracker',
      seeders: 3,
    );

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

  group('een oogst die de zeef niet overleeft, zegt dat', () {
    test('DE KERN: alles weggezeefd is iets anders dan niets gevonden', () async {
      // Zonder deze regel valt RuTracker hier stil weg: de zeef in de zoekverdeler gooit de rijen
      // weg en `catch (_) {}` eromheen slikt alles. Op het scherm zie je dan treffers van een
      // ándere bron staan en over RuTracker geen woord — precies wat er gemeld werd.
      final rt = _NepRt(AppSettings(), [_treffer('Concert 2011 1080p x264')]);
      final bron = RuTrackerSource(rt);
      expect(await bron.search('iets'), hasLength(1), reason: 'de bron geeft door wat hij vond');
      expect(rt.lastError, contains('zeef'));
      expect(rt.lastError, contains('1 resultaten'));
    });

    test('en een oogst die er wél doorkomt zegt niets', () async {
      final rt = _NepRt(AppSettings(), [_treffer('Gala - Come Into My Life [24-96] FLAC')]);
      await RuTrackerSource(rt).search('iets');
      expect(rt.lastError, isEmpty);
    });

    test('een lege oogst laat de melding van search() staan', () async {
      // search() zet daar zelf al een zin neer (geen aanmelding, sessie verlopen, Cloudflare). Die
      // mag hier niet overschreven worden door een zeefmelding die nergens over gaat.
      final rt = _NepRt(AppSettings(), const [])..lastError = 'de sessie is verlopen';
      await RuTrackerSource(rt).search('iets');
      expect(rt.lastError, 'de sessie is verlopen');
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
