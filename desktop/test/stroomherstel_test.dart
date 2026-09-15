library;

import 'package:debridmusic/netsoort.dart';
import 'package:debridmusic/player.dart';
import 'package:flutter_test/flutter_test.dart';

/// **GEMETEN OP 15-09-2026 met een server die er halverwege een nummer uitklapt.**
///
/// Saber luisterde die middag met zijn buds en de muziek viel een paar keer stil. In `speler.log`
/// van de telefoon staat vier keer hetzelfde patroon, tussen 16:43 en 17:15, terwijl hij onderweg
/// was en de stroom over Tailscale op LTE liep:
///
///     16:48:49 · 16:48:55 · 16:49:03 · 16:49:15   vier keer "Connection timed out"
///     16:50:14   AFGEBROKEN op 0:02:43 van 0:05:01 — Together Again
///     16:50:14   OPENEN MISLUKT — Error decoding audio.
///
/// Vier pogingen in zesentwintig seconden, dan een volle minuut waarin **niets** werd geprobeerd,
/// dan was de buffer leeg en stierf het nummer. De lijn was toen aantoonbaar alweer terug: het
/// volgende nummer speelde zonder klacht tot 16:54:33. Idem bij *Got Me Singing* (3:21 van 3:42) en
/// *Quit Playin' Games* (3:26 van 3:54).
///
/// De oorzaak: `reconnect` staat bij ffmpeg standaard UIT, en deze app zette hem niet aan. Nagemeten
/// met een eigen server die de verbinding op byte 3.912.986 verbreekt, zestig seconden muziek
/// gevraagd:
///
///     lijn 12 s weg    zonder    6,4 s muziek, daarna stuk
///                      met      60,0 s — alles
///     lijn 45 s weg    zonder    6,4 s
///                      met      60,0 s
///
/// Het was NIET de bluetooth: tussen 16:05 en 17:15 staat er geen enkele uitgangsverandering in het
/// logboek, dus de buds bleven die hele tijd gewoon verbonden.
void main() {
  /// De opties zoals ffmpeg ze leest: `k=v,k=v`.
  Map<String, String> ontleed(String s) => {
        for (final deel in s.split(',').where((d) => d.trim().isNotEmpty))
          deel.split('=').first.trim(): deel.split('=').skip(1).join('=').trim(),
      };

  group('opnieuw verbinden als de lijn wegvalt', () {
    test('DE KERN: reconnect staat aan, ook bij een NETWERKfout', () {
      final o = ontleed(kStroomHerstelOpties);
      expect(o['reconnect'], '1',
          reason: 'zonder dit sterft elk nummer bij de eerste hapering; ffmpeg zet het niet zelf aan');
      // `reconnect` alleen dekt een stroom die netjes eindigt. Een lijn die wégvalt is een
      // netwerkfout, en dat is precies wat er op de telefoon gebeurde.
      expect(o['reconnect_on_network_error'], '1',
          reason: 'de gemeten storing was "Connection timed out", niet een nette stroom-einde');
    });

    test('DE VAL: hij geeft eerder op dan de buffer leeg is', () {
      // Anders staat de muziek stil terwijl ffmpeg nog zit te proberen: geen geluid, geen melding,
      // en de eigen herkansing van de app komt nooit aan de beurt. Het zuinigste vooruitlezen is
      // dat op mobiele data.
      final grens = vooruitleesSeconden(Netsoort.mobiel);
      expect(kHerverbindenSeconden, lessThan(grens),
          reason: 'opgeven ná de buffer betekent stille stilstand in plaats van een foutmelding');
      expect(int.parse(ontleed(kStroomHerstelOpties)['reconnect_delay_max']!),
          kHerverbindenSeconden);
    });

    test('DE VAL: hij geeft ook niet te snel op', () {
      // De gemeten onderbrekingen duurden meer dan vijfentwintig seconden — vier mislukte
      // verbindingen in zesentwintig seconden, en daarna was het nog niet voorbij. Een venster van
      // een paar tellen had geen van de vier nummers gered.
      expect(kHerverbindenSeconden, greaterThanOrEqualTo(30),
          reason: 'korter dan de storing die het moet overbruggen is geen reparatie');
    });

    test('DE GRENS: reconnect_streamed blijft eruit', () {
      // Dat is voor bronnen die geen Range kennen; die beginnen dan van voren af aan. Halverwege
      // een nummer terugspringen naar 0:00 is erger dan stoppen. Onze eigen server kan Range —
      // zie `lan/range.dart` — dus hij is niet nodig.
      expect(ontleed(kStroomHerstelOpties).containsKey('reconnect_streamed'), isFalse);
    });

    test('DE GRENS: niets anders dan reconnect-instellingen', () {
      // Deze regel gaat ONGEFILTERD naar de stroomlaag van ffmpeg. Er hoort niets in te staan dat
      // het openen zelf kan laten mislukken — een time-out of een user-agent hoort hier niet.
      expect(ontleed(kStroomHerstelOpties).keys, everyElement(startsWith('reconnect')));
      expect(kStroomHerstelOpties, isNot(contains(' ')),
          reason: 'een spatie in een lavf-optielijst leest ffmpeg als deel van de waarde');
    });
  });
}
