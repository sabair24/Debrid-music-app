/// Het koekje uit de browser lezen, en herkennen wanneer Cloudflare ertussen staat.
///
/// **Waarom dit bestaat.** Op 23-08-2026 bleek RuTracker onbereikbaar voor de app: élk verzoek —
/// ook een kale GET van de inlogpagina — kwam terug als 403 met `Cf-Mitigated: challenge` en de
/// pagina "Just a moment...". Dat is geen wachtwoordprobleem en het is ook niet met headers te
/// verhelpen; uitgeprobeerd zonder User-Agent, met de UA van de app, en met een volledige Chrome
/// inclusief `sec-ch-ua` en `Sec-Fetch-*`. Alle drie 403.
///
/// Wat overblijft is het koekje uit een browser die de uitdaging zélf heeft opgelost. Het lezen van
/// dat plaksel is precies het soort code dat stil verkeerd gaat: één verkeerd geknipte regel en de
/// app stuurt een half koekje, met dezelfde 403 als gevolg en niets dat uitlegt waarom.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/rutracker.dart';

void main() {
  group('het plaksel lezen', () {
    test('uit "Kopieer als cURL" komen de koekjes én het browserkenmerk', () {
      const plaksel = '''
curl 'https://rutracker.org/forum/index.php' \
  -H 'accept: text/html,application/xhtml+xml' \
  -H 'accept-language: ru,en;q=0.9' \
  -H 'cookie: cf_clearance=Xy9_abc-123; bb_session=0-12345-abcdef; bb_t=eJxrYA' \
  -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36'
''';
      final g = RuTrackerService.leesPlaksel(plaksel)!;

      expect(g.heeftClearance, isTrue);
      expect(g.heeftSessie, isTrue);
      expect(g.cookie, contains('cf_clearance=Xy9_abc-123'));
      expect(g.cookie, contains('bb_session=0-12345-abcdef'));
      // Alles wat de browser meestuurt blijft staan: Cloudflare kijkt naar meer dan cf_clearance.
      expect(g.cookie, contains('bb_t=eJxrYA'));
      expect(g.ua, contains('Chrome/139.0.0.0'));
    });

    test('ook de Windows-vorm met dubbele aanhalingstekens', () {
      const plaksel = 'curl "https://rutracker.org/forum/tracker.php" ^\n'
          '  -H "cookie: cf_clearance=q1; bb_session=q2" ^\n'
          '  -H "user-agent: Mozilla/5.0 (Windows NT 10.0) Chrome/139.0.0.0"';
      final g = RuTrackerService.leesPlaksel(plaksel)!;

      expect(g.cookie, 'cf_clearance=q1; bb_session=q2');
      expect(g.ua, contains('Chrome/139.0.0.0'));
    });

    test('een kale koekjesregel mag ook, dan blijft het kenmerk leeg', () {
      final g = RuTrackerService.leesPlaksel('cf_clearance=aaa; bb_session=bbb')!;

      expect(g.cookie, 'cf_clearance=aaa; bb_session=bbb');
      expect(g.ua, isEmpty, reason: 'niets gevonden is iets anders dan een verzonnen kenmerk');
      expect(g.heeftClearance, isTrue);
    });

    test('en met "Cookie:" ervoor, zoals je hem uit de koppen kopieert', () {
      final g = RuTrackerService.leesPlaksel('Cookie: bb_session=alleen-de-sessie')!;

      expect(g.cookie, 'bb_session=alleen-de-sessie');
      expect(g.heeftSessie, isTrue);
      // Zonder cf_clearance kom je niet langs de deur — dat hoort gezegd te worden, niet geraden.
      expect(g.heeftClearance, isFalse);
    });

    test('wat geen koekje is levert niets op', () {
      expect(RuTrackerService.leesPlaksel(''), isNull);
      expect(RuTrackerService.leesPlaksel('   '), isNull);
      expect(RuTrackerService.leesPlaksel('ik heb geen idee wat hier hoort'), isNull);
    });
  });

  group('Cloudflare herkennen', () {
    test('aan de kop die hij zelf zet', () {
      expect(
          RuTrackerService.cloudflareUitdaging(
              {'server': 'cloudflare', 'cf-mitigated': 'challenge'}, ''),
          isTrue);
    });

    test('aan de wachtpagina', () {
      expect(
          RuTrackerService.cloudflareUitdaging({'server': 'cloudflare'},
              '<html><head><title>Just a moment...</title></head><body></body></html>'),
          isTrue);
    });

    test('maar niet aan een gewone RuTracker-pagina', () {
      expect(
          RuTrackerService.cloudflareUitdaging({'server': 'cloudflare', 'content-type': 'text/html'},
              '<html><title>RuTracker.org</title><form action="login.php"></form></html>'),
          isFalse,
          reason: 'anders leest een fout wachtwoord straks als een uitdaging');
    });
  });

  group('de vorm die Chrome zelf uitspuugt', () {
    test('koekjes staan achter -b, zonder het woord "cookie"', () {
      // Precies waar de eerste poging op strandde: Chrome 151 exporteert de koekjes als
      // `-b 'naam=waarde; ...'`. De lezer zocht alleen naar `-H 'cookie: ...'`, vond niets, en het
      // scherm meldde dat cf_clearance ontbrak terwijl hij er gewoon in stond.
      const plaksel = """
curl --url 'https://rutracker.org/forum/index.php' \
  -H 'accept: text/html' \
  -b 'bb_guid=aa; bb_ssl=1; bb_session=0-27713872-tth6; cf_clearance=ZmQDgB0xMfG-1787499836-1.2.1.1-Uou' \
  -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/151.0.0.0 Safari/537.36'
""";
      final g = RuTrackerService.leesPlaksel(plaksel)!;

      expect(g.heeftClearance, isTrue);
      expect(g.heeftSessie, isTrue);
      expect(g.cookie, contains('cf_clearance=ZmQDgB0xMfG-1787499836-1.2.1.1-Uou'));
      expect(g.cookie, contains('bb_guid=aa'));
      expect(g.ua, contains('Chrome/151.0.0.0'));
    });
  });

  group('het verzoek dat langs curl gaat', () {
    test('draagt het koekje, het kenmerk, en volgt geen omleiding', () {
      final a = RuTrackerService.curlArgumenten(
          'https://rutracker.org/forum/tracker.php', 'cf_clearance=x; bb_session=y', 'Chrome/151', '/tmp/uit');

      expect(a, containsAllInOrder(['-A', 'Chrome/151']));
      expect(a, containsAllInOrder(['-b', 'cf_clearance=x; bb_session=y']));
      // Een 302 naar login.php IS het antwoord (sessie verlopen) — dat mag curl niet wegslikken.
      expect(a, contains('--no-location'));
      expect(a, containsAllInOrder(['-o', '/tmp/uit']));
      expect(a.last, 'https://rutracker.org/forum/tracker.php');
      // Niet uitgepakt: het antwoord is windows-1251 en wordt als losse bytes gelezen.
      expect(a, isNot(contains('--compressed')));
    });

    test('en laat -b weg als er geen koekje is', () {
      final a = RuTrackerService.curlArgumenten('https://rutracker.org/forum/', '', 'Chrome/151', '/tmp/uit');
      expect(a, isNot(contains('-b')));
    });
  });
}
