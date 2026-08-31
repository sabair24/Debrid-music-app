/// Het koekje dat de app voortaan zelf ophaalt.
///
/// **Waarom dit bestaat.** RuTracker staat achter Cloudflare, en het `cf_clearance`-koekje daarvoor
/// kwam uit Chrome: netwerktab open, "Kopieer als cURL", plakken in de instellingen. Elke keer als
/// dat koekje verliep opnieuw. FlareSolverr kan het halen — maar er zitten twee dingen in die stil
/// fout gaan, en allebei kosten ze de toegang tot RuTracker:
///
///  1. het antwoord verkeerd lezen, en een leeg koekje over een werkend heen schrijven;
///  2. het hele koekje VERVANGEN in plaats van aanvullen — dan ben je Cloudflare voorbij en meteen
///     uitgelogd, want `bb_session` zit niet in wat FlareSolverr teruggeeft.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/flaresolverr.dart';
import 'package:debridmusic/rutracker.dart';

void main() {
  group('het antwoord van FlareSolverr lezen', () {
    // Letterlijk de vorm die hij op 29-08-2026 teruggaf voor rutracker.org.
    const echt = '''
{"status":"ok","message":"Challenge not detected!",
 "solution":{"url":"https://rutracker.org/forum/index.php","status":200,
   "cookies":[{"name":"cf_clearance","value":"abc123","expires":-1},
              {"name":"bb_guid","value":"xyz789","expires":-1}],
   "userAgent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/142.0.0.0 Safari/537.36"}}''';

    test('koekjes en het browserkenmerk komen eruit', () {
      final u = FlareSolverr.leesAntwoord(echt)!;

      expect(u.cookie, 'cf_clearance=abc123; bb_guid=xyz789');
      expect(u.ua, contains('Chrome/142.0.0.0'));
      expect(u.status, 200);
      expect(u.heeftClearance, isTrue);
    });

    test('zonder cf_clearance is er niets verse te melden', () {
      // Dit gebeurt echt: daagt Cloudflare op dat moment niemand uit, dan komt er een gewone
      // pagina terug zonder clearance-koekje. Dat is geen fout, maar ook geen vers koekje.
      const zonder = '{"status":"ok","solution":{"status":200,"cookies":[],"userAgent":"X"}}';
      final u = FlareSolverr.leesAntwoord(zonder)!;

      expect(u.cookie, isEmpty);
      expect(u.heeftClearance, isFalse);
    });

    test('een mislukking levert niets op in plaats van iets leegs', () {
      expect(FlareSolverr.leesAntwoord('{"status":"error","message":"boem"}'), isNull);
      expect(FlareSolverr.leesAntwoord('<html>geen json</html>'), isNull);
      expect(FlareSolverr.leesAntwoord(''), isNull);
    });
  });

  group('koekjes samenvoegen', () {
    test('DE KERN: de sessie blijft staan, de clearance wordt ververst', () {
      // Zou dit vervangen in plaats van samenvoegen, dan komt de app wél door Cloudflare heen en
      // staat daarna uitgelogd binnen: geen downloadknoppen, geen .torrent, geen uitleg.
      const bestaand = 'bb_session=IK-BEN-HET; bb_guid=oud; cf_clearance=VERLOPEN';
      const vanFs = 'cf_clearance=VERS; bb_guid=nieuw';

      final uit = RuTrackerService.voegKoekjesSamen(bestaand, vanFs);

      expect(uit, contains('bb_session=IK-BEN-HET'));
      expect(uit, contains('cf_clearance=VERS'));
      expect(uit, isNot(contains('VERLOPEN')));
      expect(uit, contains('bb_guid=nieuw'));
    });

    test('geen dubbele namen, ook niet met rare witruimte', () {
      final uit = RuTrackerService.voegKoekjesSamen('a=1;  b=2 ', 'a=3');

      expect(uit.split('; ').length, 2);
      expect(uit, contains('a=3'));
      expect(uit, contains('b=2'));
    });

    test('een lege kant verandert niets', () {
      expect(RuTrackerService.voegKoekjesSamen('a=1; b=2', ''), 'a=1; b=2');
      expect(RuTrackerService.voegKoekjesSamen('', 'a=1'), 'a=1');
    });

    test('waarden met een = erin blijven heel', () {
      // Een cf_clearance eindigt vaak op base64 met `=` erin. Splitsen op élke `=` maakt daar een
      // half koekje van, en dat is precies het soort stille fout dat een 403 oplevert.
      final uit = RuTrackerService.voegKoekjesSamen('', 'cf_clearance=aGVsbG8=');

      expect(uit, 'cf_clearance=aGVsbG8=');
    });
  });

  group('het adres van FlareSolverr', () {
    test('het pad wordt er niet twee keer aan geplakt', () {
      // Mensen kopiëren het adres inclusief /v1 uit de documentatie.
      expect(FlareSolverr('http://127.0.0.1:8191').ingesteld, isTrue);
      expect(FlareSolverr('').ingesteld, isFalse);
    });
  });
}
