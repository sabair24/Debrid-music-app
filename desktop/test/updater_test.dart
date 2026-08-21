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
      // DEZE regel heeft zijn werk al gedaan. Hij zakte bij de eerste echte uitvoering: de functie
      // haalde wel een `v` weg maar niet het `win-` ervoor, en gaf `win-v3.9.141` terug. Dat leest
      // [vergelijkVersies] als 0.9.141 — nul is lager dan alles, dus de pc had nooit een update
      // aangeboden. Stil, want aan een venster dat niet komt valt niets te zien.
      expect(versieUit('win-v3.9.141'), '3.9.141');
      expect(versieUit('3.9.141'), '3.9.141');
      // De Apple-tag heeft weer een ander voorvoegsel; hij komt hier niet langs, maar de vorm mag
      // geen derde geval worden waar iemand later achterkomt.
      expect(versieUit('apple-v1.0.2'), '1.0.2');
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

    test('de zip van de Mac, en niet de installer', () {
      final assets = lijst(['DebridMusic-Setup-v3.9.152.exe', 'DebridMusic-macOS-3.9.152.zip']);
      expect(macZipUit(assets)?['name'], 'DebridMusic-macOS-3.9.152.zip');
      // Een release met alleen Windows erin levert voor de Mac niets op -- en dat hoort geen gok te
      // worden: een willekeurige zip binnenhalen en uitpakken over je app heen is erger dan niets.
      expect(macZipUit(lijst(['DebridMusic-Setup-v3.9.152.exe'])), isNull);
      expect(macZipUit(lijst(['bronnen.zip'])), isNull);
      expect(macZipUit(const []), isNull);
    });

    test('rommel in de lijst laat de rest staan', () {
      expect(apkUit(['geen map', 42, ...lijst(['app.apk'])])?['name'], 'app.apk');
    });
  });

  group('waar staat de draaiende Mac-app', () {
    test('het pakket zit drie mappen boven het uitvoerbare bestand', () {
      expect(bundelUit('/Applications/DebridMusic.app/Contents/MacOS/DebridMusic'),
          '/Applications/DebridMusic.app');
      // Een pad met spaties erin is doodgewoon op een Mac.
      expect(bundelUit('/Users/ik/Mijn Apps/DebridMusic.app/Contents/MacOS/DebridMusic'),
          '/Users/ik/Mijn Apps/DebridMusic.app');
    });

    test('alles wat er niet exact op lijkt levert niets', () {
      // Onder `flutter run` draait de app niet uit een pakket. Dan hoort er niets geruild te
      // worden -- wat hierna komt VERPLAATST mappen, en gokken is daar het laatste wat je wilt.
      expect(bundelUit('/Users/ik/project/build/debug/debridmusic'), isNull);
      // Wel een .app in het pad, maar niet als pakket eromheen.
      expect(bundelUit('/Applications/DebridMusic.app/Contents/Resources/hulpje'), isNull);
      expect(bundelUit('/Applications/DebridMusic.app'), isNull);
      expect(bundelUit(''), isNull);
    });
  });

  group('het ruilscript', () {
    final script = ruilScript(
      pid: 4242,
      pakket: '/Applications/DebridMusic.app',
      nieuw: '/tmp/update/uitgepakt/DebridMusic.app',
      terzijde: '/tmp/update/vorige.app',
    );

    test('het wacht tot deze app echt weg is', () {
      // Zonder dit verplaatst het script de map waar de app op dat moment uit leest.
      expect(script, contains('kill -0 "\$PID"'));
      expect(script, contains('PID=4242'));
    });

    test('de oude versie gaat opzij en wordt pas daarna weggegooid', () {
      // De volgorde is het hele vangnet: verplaatsen kan terug, verwijderen niet.
      final opzij = script.indexOf('mv "\$PAKKET" "\$TERZIJDE"');
      final weg = script.indexOf('rm -rf "\$TERZIJDE"', opzij);
      expect(opzij, greaterThan(-1));
      expect(weg, greaterThan(opzij));
    });

    test('mislukt het uitpakken, dan komt de oude terug', () {
      expect(script, contains('mv "\$TERZIJDE" "\$PAKKET"'));
      // En er wordt hoe dan ook iets opgestart, ook na die terugval.
      expect(script.trimRight(), endsWith('open "\$PAKKET"'));
    });

    test('paden staan tussen aanhalingstekens, ook met een apostrof erin', () {
      final raar = ruilScript(
        pid: 1,
        pakket: "/Users/ik/Ann's Mac/DebridMusic.app",
        nieuw: '/tmp/n.app',
        terzijde: '/tmp/v.app',
      );
      // Een enkele apostrof zou het script anders halverwege afkappen en `rm -rf` op iets anders
      // laten los gaan.
      expect(raar, contains(r"PAKKET='/Users/ik/Ann'\''s Mac/DebridMusic.app'"));
    });
  });
}
