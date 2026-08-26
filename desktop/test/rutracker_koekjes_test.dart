/// De koekjes uit het aanmeldvenster: welke er meekomen, en waarom er één ontbrak.
///
/// **Waarom hier een toets op staat.** Het venster deed het niet, en de reden was geen storing maar
/// een pad. Een koekje hoort bij een pad, en RuTracker zet `bb_session` onder `/forum/` — daar staat
/// het forum. De app vroeg de koekjeslade om `https://rutracker.org`, dus pad `/`, en kreeg dat
/// koekje niet terug. Het pad paste niet.
///
/// Wat je dan ziet is wat er ook echt gebeurde: je bent aantoonbaar ingelogd — je naam staat
/// linksboven op de pagina — en het venster blijft zeggen "Bezig met laden…". Er kwam een lege
/// lijst binnen, en een lege lijst las als "nog niets".
///
/// Het samenvoegen zelf is zuivere tekstverwerking, en dat is precies het stuk dat stil fout kan
/// gaan. De koekjeslade van het toestel is hier niet te draaien; wat eruit komt wél.
library;

import 'package:debridmusic/rutracker_login.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kort schrijven wat de lade teruggeeft.
List<({String naam, String waarde})> lade(Map<String, String> paren) =>
    [for (final e in paren.entries) (naam: e.key, waarde: e.value)];

void main() {
  group('DE KERN: het koekje van het forumpad komt mee', () {
    test('de wortel kent bb_session niet, het forumpad wel', () {
      // Dit is de meting nagespeeld: pad `/` geeft alleen wat Cloudflare neerzette, pad `/forum/`
      // geeft de aanmelding. Kijk je maar op één van de twee, dan mis je de helft.
      final wortel = lade({'cf_clearance': 'abc123'});
      final forum = lade({'bb_session': 'zzz999'});
      final kop = voegKoekjesSamen([forum, wortel]);
      expect(kop, contains('bb_session=zzz999'));
      expect(kop, contains('cf_clearance=abc123'));
    });

    test('en zonder het forumpad zou je precies dat missen', () {
      // De oude toestand, expliciet vastgelegd zodat hij niet terug kan sluipen.
      final alleenWortel = voegKoekjesSamen([lade({'cf_clearance': 'abc123'})]);
      expect(alleenWortel.contains('bb_session='), isFalse);
    });

    test('de adressen staan van smal naar breed', () {
      // De volgorde is geen smaak: het smalste pad is het meest specifieke, en dat hoort te winnen
      // als dezelfde naam op twee plekken staat.
      expect(kRutrackerKoekjeUrls.first, 'https://rutracker.org/forum/');
      expect(kRutrackerKoekjeUrls, contains('https://rutracker.org/'));
    });
  });

  group('samenvoegen', () {
    test('de eerste waarde wint, want die komt van het smalste pad', () {
      final kop = voegKoekjesSamen([
        lade({'bb_session': 'nieuw'}),
        lade({'bb_session': 'oud'}),
      ]);
      expect(kop, 'bb_session=nieuw');
    });

    test('een gewist koekje telt niet mee', () {
      // Een lege waarde is hoe een browser een koekje weggooit. Die mag geen echte overschrijven,
      // en mag ook niet als "er is een sessie" gelezen worden.
      final kop = voegKoekjesSamen([
        lade({'bb_session': ''}),
        lade({'bb_session': 'echt'}),
      ]);
      expect(kop, 'bb_session=echt');
      expect(voegKoekjesSamen([lade({'bb_session': ''})]), '');
    });

    test('niets erin is niets eruit', () {
      expect(voegKoekjesSamen([]), '');
      expect(voegKoekjesSamen([[], []]), '');
    });

    test('de vorm is die van een Cookie-kop', () {
      final kop = voegKoekjesSamen([
        lade({'bb_session': 'a', 'cf_clearance': 'b', 'bb_ssl': '1'}),
      ]);
      expect(kop, 'bb_session=a; cf_clearance=b; bb_ssl=1');
    });
  });

  group('document.cookie als aanvulling', () {
    test('een gewone regel valt uiteen in paren', () {
      final paren = leesDocumentCookie('bb_session=abc; bb_ssl=1; opt-viewtopic=1');
      expect(paren.map((p) => p.naam), ['bb_session', 'bb_ssl', 'opt-viewtopic']);
      expect(paren.first.waarde, 'abc');
    });

    test('een waarde met een = erin blijft heel', () {
      // Base64 eindigt op = en dat komt in sessiekoekjes echt voor. Splitsen op elke = maakt daar
      // stilletjes een afgeknipt koekje van.
      final paren = leesDocumentCookie('t=YWJjZA==');
      expect(paren.single.waarde, 'YWJjZA==');
    });

    test('een lege regel levert niets op', () {
      expect(leesDocumentCookie(''), isEmpty);
      expect(leesDocumentCookie('  '), isEmpty);
    });

    test('DE KERN: hij vult de lade aan in plaats van hem te vervangen', () {
      // cf_clearance is HttpOnly en staat dus NOOIT in document.cookie. Zou de pagina de lade
      // vervangen, dan gooi je precies het koekje weg dat Cloudflare openhoudt.
      final kop = voegKoekjesSamen([
        lade({'cf_clearance': 'httponly-waarde'}),
        leesDocumentCookie('bb_session=uit-de-pagina'),
      ]);
      expect(kop, contains('cf_clearance=httponly-waarde'));
      expect(kop, contains('bb_session=uit-de-pagina'));
    });
  });

  group('wat de sessie erover zegt', () {
    test('bb_session is aangemeld, cf_clearance alleen is dat niet', () {
      const alleenDoorgang = RtSessie(cookie: 'cf_clearance=x', ua: '');
      expect(alleenDoorgang.heeftSessie, isFalse);
      expect(alleenDoorgang.heeftClearance, isTrue);

      const binnen = RtSessie(cookie: 'cf_clearance=x; bb_session=y', ua: 'Mozilla/5.0');
      expect(binnen.heeftSessie, isTrue);
      expect(binnen.heeftClearance, isTrue);
    });
  });
}
