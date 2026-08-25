/// Wat de gebruiker zelf uit de Soulseek-lijst koos mag niet door een automatische regel worden
/// weggeschoven.
///
/// De klacht die dit veroorzaakte: bij Joe Dassin / *L'été indien* is de best gerangschikte kopie een
/// ánder nummer, dus koos Saber er zelf een uit de lijst. Die kwam netjes binnen — en stond later in
/// `_dubbel`. Niet weg, wel weggeschoven, en zonder melding.
///
/// De schuldige is de LAATSTE grond van [firstIsBetter]: grootte. Een 4:16-versie van een ander
/// nummer is nu eenmaal groter dan de 3:37 die je wilde. Daarom zit de bescherming in die functie en
/// niet bij de aanroepers — dat is het enige punt waar élke opruimweg langskomt.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/organize.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/vaste_keuze.dart';

import 'place_file_test.dart' show buildFlac;

void main() {
  late Directory scratch;

  File maak(String naam, int bytes) {
    final f = File('${scratch.path}${Platform.pathSeparator}$naam');
    f.writeAsBytesSync(List<int>.filled(bytes, 0));
    return f;
  }

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_vastekeuze_');
    setAppDirForTest(scratch.path);
    resetVasteKeuzesForTest();
  });

  tearDown(() {
    resetVasteKeuzesForTest();
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('firstIsBetter', () {
    test('zonder bescherming wint de grootste — dit is wat er misging', () {
      final klein = maak('gekozen.flac', 1000);
      final groot = maak('ander.flac', 2000);
      expect(firstIsBetter(groot, klein), isTrue);
      expect(firstIsBetter(klein, groot), isFalse, reason: 'precies zo verdween L\'été indien');
    });

    test('een handmatige keuze verliest niet van een groter bestand', () async {
      final gekozen = maak('gekozen.flac', 1000);
      final groot = maak('ander.flac', 2000);
      await onthoudVasteKeuze(gekozen.path);

      expect(firstIsBetter(gekozen, groot), isTrue);
      expect(firstIsBetter(groot, gekozen), isFalse);
    });

    test('ook niet van een beter FORMAAT — de bescherming staat boven alle drie de gronden', () async {
      // Grootte was de aanleiding, maar formaat en stereo/surround zouden hetzelfde doen. Een FLAC die
      // een handmatig gekozen mp3 verdringt is even ongewenst als een grotere kopie.
      final gekozen = maak('gekozen.mp3', 1000);
      final flac = maak('ander.flac', 5000);
      expect(firstIsBetter(flac, gekozen), isTrue, reason: 'FLAC boven mp3, zoals het hoort');

      await onthoudVasteKeuze(gekozen.path);
      expect(firstIsBetter(flac, gekozen), isFalse);
      expect(firstIsBetter(gekozen, flac), isTrue);
    });

    test('twee handmatige keuzes worden gewoon op kwaliteit vergeleken', () async {
      // Dan heeft de gebruiker twee keer gekozen en valt er geen voorkeur af te lezen. Bewust GEEN
      // slot op het bestand: dit is een voorrangsregel, geen bevriezing.
      final a = maak('a.flac', 1000);
      final b = maak('b.flac', 2000);
      await onthoudVasteKeuze(a.path);
      await onthoudVasteKeuze(b.path);
      expect(firstIsBetter(b, a), isTrue);
    });

    test('vergeten haalt de bescherming er ook echt weer af', () async {
      final gekozen = maak('gekozen.flac', 1000);
      final groot = maak('ander.flac', 2000);
      await onthoudVasteKeuze(gekozen.path);
      expect(firstIsBetter(groot, gekozen), isFalse);
      await vergeetVasteKeuze(gekozen.path);
      expect(firstIsBetter(groot, gekozen), isTrue);
    });
  });

  group('de uitleg zegt dezelfde grond als de beslissing', () {
    test('bij een beschermd bestand gaat het niet over megabytes', () async {
      final gekozen = maak('gekozen.flac', 1000);
      final groot = maak('ander.flac', 2000);
      await onthoudVasteKeuze(gekozen.path);
      final reden = whyBetter(gekozen, groot);
      expect(reden, isNot(contains('MB')),
          reason: 'de grootte besliste juist NIET; dat zeggen is het scherm iets anders laten beweren');
      expect(reden.toLowerCase(), contains('gekozen'));
    });
  });

  group('het pad', () {
    test('hoofdletters en scheidingstekens maken geen verschil', () async {
      final f = maak('Gekozen.flac', 1000);
      await onthoudVasteKeuze(f.path);
      expect(isVasteKeuze(f.path.toUpperCase()), isTrue);
      expect(isVasteKeuze(f.path.replaceAll('\\', '/')), isTrue);
    });

    test('de bescherming verhuist mee als het bestand verplaatst wordt', () async {
      // Zonder dit gold een keuze precies één keer: het filen van een download verplaatst het bestand
      // van de landingsmap naar Albums/…, en daarna wees de lijst naar een pad dat niet meer bestaat.
      final van = maak('gekozen.flac', 1000);
      await onthoudVasteKeuze(van.path);
      final naar = File('${scratch.path}${Platform.pathSeparator}verplaatst.flac');

      await moveWithRetry(van, naar);

      expect(isVasteKeuze(van.path), isFalse, reason: 'het oude pad bestaat niet meer');
      expect(isVasteKeuze(naar.path), isTrue);

      final groot = maak('ander.flac', 2000);
      expect(firstIsBetter(groot, naar), isFalse, reason: 'en de bescherming werkt op het nieuwe pad');
    });
  });

  group('de hele keten: filen mag een keuze niet parkeren', () {
    // De echte weg waarlangs L'été indien verdween. `placeFileDetailed` stuurt een nieuwe kopie naar
    // het bestaande bestand, en dan beslist [firstIsBetter]. Zonder bescherming won de grotere en ging
    // de handmatig gekozen kopie naar `_dubbel`.

    test('een grotere kopie verdringt de handmatig gekozen niet', () async {
      final root = Directory('${scratch.path}${Platform.pathSeparator}muziek')..createSync();

      File inkomend(String naam, int seconden, int vulling) {
        final d = Directory('${root.path}${Platform.pathSeparator}_inkomend$naam')
          ..createSync(recursive: true);
        final f = File('${d.path}${Platform.pathSeparator}$naam');
        f.writeAsBytesSync([
          ...buildFlac(const ['TITLE=L\'été indien', 'ARTIST=Joe Dassin', 'ALBUM=Test', 'TRACKNUMBER=3'],
              seconds: seconden),
          ...List<int>.filled(vulling, 0),
        ]);
        return f;
      }

      // De keuze van de gebruiker komt binnen en wordt gemarkeerd, zoals de downloadweg dat doet.
      final keuze = inkomend('gekozen.flac', 217, 1000); // 3:37
      await onthoudVasteKeuze(keuze.path);
      final eerste = await placeFileDetailed(keuze, root.path);
      expect(eerste.how, Placement.moved);
      expect(isVasteKeuze(eerste.path), isTrue, reason: 'de markering moet mee verhuisd zijn');

      // En dan komt er automatisch een grotere kopie van hetzelfde nummer binnen. MET `staatAl`, want
      // dat is de echte downloadweg: alleen dan wordt de verliezer geparkeerd in plaats van gewist, en
      // juist dat parkeren was de klacht.
      final groter = inkomend('automatisch.flac', 217, 90000);
      final tweede = await placeFileDetailed(groter, root.path,
          staatAl: (artiest, titel, {int? seconds}) => eerste.path);

      expect(tweede.how, Placement.duplicate, reason: 'de nieuwe kopie verliest en wordt weggegooid');
      expect(File(eerste.path).existsSync(), isTrue, reason: 'de keuze staat er nog');
      expect(isVasteKeuze(eerste.path), isTrue);
      expect(Directory('${root.path}${Platform.pathSeparator}$parkeerMap').existsSync(), isFalse,
          reason: 'en er is niets naar _dubbel geschoven');
    });
  });

  group('bewaren en teruglezen', () {
    test('een keuze overleeft een herstart', () async {
      final f = maak('gekozen.flac', 1000);
      await onthoudVasteKeuze(f.path);
      expect(File('${scratch.path}${Platform.pathSeparator}vaste_keuzes.json').existsSync(), isTrue);

      // Nieuw proces, zelfde map.
      resetVasteKeuzesForTest();
      expect(isVasteKeuze(f.path), isFalse, reason: 'nog niet ingelezen');
      await laadVasteKeuzes();
      expect(isVasteKeuze(f.path), isTrue);
    });

    test('de lijst wordt gesorteerd weggeschreven', () async {
      await onthoudVasteKeuze('${scratch.path}${Platform.pathSeparator}b.flac');
      await onthoudVasteKeuze('${scratch.path}${Platform.pathSeparator}a.flac');
      final rauw = File('${scratch.path}${Platform.pathSeparator}vaste_keuzes.json').readAsStringSync();
      expect(rauw.indexOf('a.flac'), lessThan(rauw.indexOf('b.flac')),
          reason: 'gesorteerd, zodat het bestand niet bij elke schrijfbeurt anders oogt');
    });

    test('een onleesbaar bestand kost de app niets', () async {
      File('${scratch.path}${Platform.pathSeparator}vaste_keuzes.json').writeAsStringSync('{kapot');
      resetVasteKeuzesForTest();
      await laadVasteKeuzes();
      expect(vasteKeuzesGeladen, isTrue);
      expect(erZijnVasteKeuzes, isFalse, reason: 'geen bescherming, maar ook geen storing');
    });
  });
}
