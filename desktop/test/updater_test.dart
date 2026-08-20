/// Bijwerken vanuit de app: de getallen en de bestandskeuze.
///
/// **Waarom dit bestaat.** Een updater faalt op precies twee manieren, en allebei stil. Hij biedt
/// niets aan terwijl er wél iets is (dan loop je maanden achter zonder het te weten — wat hier
/// gebeurd is), of hij biedt iets aan dat het toestel vervolgens weigert (dan lijkt de updater
/// stuk). Beide komen neer op één vergelijking en één keuze uit een lijst bestanden, en dat is
/// precies wat hier zonder toestel te toetsen valt.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/updater.dart';

void main() {
  group('het buildnummer uit de tag', () {
    test('leest de tag die de bouwstraat schrijft', () {
      expect(buildnummerUit('v3.9.74-build11037'), 11037);
      expect(buildnummerUit('v3.9.74-build11014'), 11014);
    });

    test('alles wat er niet op lijkt levert niets, en geen gok', () {
      // Een verkeerd gelezen nummer is erger dan geen nummer: dan biedt de app een update aan die
      // Android daarna weigert, en dat leest als een kapotte updater.
      expect(buildnummerUit('win-v3.9.141'), isNull);
      expect(buildnummerUit('v3.9.74'), isNull);
      expect(buildnummerUit(''), isNull);
      expect(buildnummerUit('build'), isNull);
    });

    test('de versienaam komt uit dezelfde tag', () {
      expect(versieUit('v3.9.74-build11037'), '3.9.74');
      expect(versieUit('win-v3.9.141'), '3.9.141');
      expect(versieUit('3.9.141'), '3.9.141');
    });
  });

  group('is het nieuwer', () {
    test('hoger is nieuwer, gelijk niet', () {
      expect(isNieuwer(hier: 11028, daar: 11037), isTrue);
      // Gelijk moet onwaar zijn, anders biedt de app zichzelf aan — elke start opnieuw.
      expect(isNieuwer(hier: 11037, daar: 11037), isFalse);
    });

    test('lager is nooit nieuwer', () {
      // Geen theoretisch geval: er zijn APK's op de pc gebouwd met nummers 10830-10844, vóór de
      // teller van de bouwstraat. Android weigert die als een stap terug.
      expect(isNieuwer(hier: 11037, daar: 10844), isFalse);
    });
  });

  group('versienamen vergelijken (de pc)', () {
    test('per getal en niet als tekst', () {
      // DE test. Als tekst is "3.9.9" nieuwer dan "3.9.141", want de 9 wint van de 1 — en dat is
      // precies het bereik waar deze app nu in zit.
      expect(vergelijkVersies('3.9.141', '3.9.9'), greaterThan(0));
      expect(vergelijkVersies('3.9.9', '3.9.141'), lessThan(0));
    });

    test('gelijk is gelijk, met of zonder v ervoor', () {
      expect(vergelijkVersies('3.9.141', '3.9.141'), 0);
      expect(vergelijkVersies('v3.9.141', '3.9.141'), 0);
    });

    test('een ontbrekend deel telt als nul', () {
      expect(vergelijkVersies('3.10', '3.9.141'), greaterThan(0));
      expect(vergelijkVersies('3.9', '3.9.0'), 0);
    });

    test('rommel maakt er geen nieuwere versie van', () {
      expect(vergelijkVersies('kapot', '3.9.141'), lessThan(0));
    });
  });

  group('welk bestand uit de release', () {
    List<Map<String, dynamic>> lijst(List<String> namen) =>
        [for (final n in namen) {'name': n, 'browser_download_url': 'https://x/$n', 'size': 1}];

    test('de APK, en alleen de APK', () {
      expect(apkUit(lijst(['DebridMusic-v3.9.74-build11037.apk']))?['name'],
          'DebridMusic-v3.9.74-build11037.apk');
      // Een controlebestand mag nooit als installatiebestand doorgaan.
      expect(apkUit(lijst(['DebridMusic.apk.sha256'])), isNull);
      expect(apkUit(const []), isNull);
    });

    test('de installer, niet de zip van de Mac', () {
      // In dezelfde release hangen allebei. Op naam én extensie, want ".exe" alleen zou ook een
      // los hulpprogramma pakken en ".zip" is de Mac-app.
      final assets = lijst(['DebridMusic-macOS-3.9.141.zip', 'DebridMusic-Setup-v3.9.141.exe']);
      expect(installerUit(assets)?['name'], 'DebridMusic-Setup-v3.9.141.exe');
      expect(installerUit(lijst(['DebridMusic-macOS-3.9.141.zip'])), isNull);
    });

    test('rommel in de lijst laat de rest staan', () {
      expect(apkUit(['geen map', 42, ...lijst(['app.apk'])])?['name'], 'app.apk');
    });
  });
}
