/// De catalogus van de pc: ontleden op een andere isolate, en bewaren zonder hem terug te coderen.
///
/// **Waarom dit bestaat.** Bij een gekoppeld toestel doet de pc het werk en stuurt hij zijn hele
/// bibliotheek door — bij duizend nummers megabytes JSON. Op de telefoon gebeurde daar tweemaal iets
/// zwaars mee op de tekendraad: `jsonDecode` bij binnenkomst, en `jsonEncode` om diezelfde inhoud als
/// kopie op schijf te zetten.
///
/// Dat viel niet op zolang het zelden gebeurde: de telefoon vraagt elke vijftien seconden of er iets
/// veranderd is, en normaal is het antwoord een lege 304. Maar tijdens een download verandert de
/// bibliotheek van de pc bij élk binnengekomen nummer — dus kwam er elke vijftien seconden een
/// volledige catalogus binnen, en stond de telefoon vier keer per minuut stil. Gemeld op 27-08-2026:
/// *"vanaf ik download via torrent hapert de app enorm, zelfs roteren is massa's traag"*. Roteren
/// bouwt de hele boom opnieuw op, en dat kwam er bovenop.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/catalogus_kopie.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/paths.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(Object json) => Uint8List.fromList(utf8.encode(jsonEncode(json)));

void main() {
  group('DE KERN: ontleden gebeurt niet op de tekendraad', () {
    test('een gewoon antwoord komt er als kaart uit', () async {
      final uit = await ontleedCatalogus(_bytes({
        'tracks': [
          {'id': 't1', 'title': 'Saturday Night'}
        ],
        'albums': const [],
      }));
      expect(uit, isNotNull);
      expect((uit!['tracks'] as List).length, 1);
    });

    test('cyrillische tekens overleven de overtocht', () async {
      // De bytes gaan als bytes naar de andere isolate en worden daar pas gedecodeerd. Wie ze
      // onderweg als tekst behandelt, verliest precies dit.
      final uit = await ontleedCatalogus(_bytes({'naam': 'Кино'}));
      expect(uit!['naam'], 'Кино');
    });

    test('een groot antwoord komt heel terug', () async {
      // Duizend nummers is de maat waar de klacht over ging. Hier gaat het om de overtocht: een
      // isolate kopieert wat je meegeeft, en dat moet in één stuk aankomen.
      final groot = {
        'tracks': [
          for (var i = 0; i < 1000; i++) {'id': 't$i', 'title': 'Nummer $i'}
        ]
      };
      final uit = await ontleedCatalogus(_bytes(groot));
      expect((uit!['tracks'] as List).length, 1000);
      expect(((uit['tracks'] as List).last as Map)['title'], 'Nummer 999');
    });

    test('rommel geeft null in plaats van een uitzondering', () async {
      // Een uitzondering uit een isolate komt op een andere plek naar buiten dan de aanroeper
      // verwacht. De aanroeper maakt hier zelf een nette melding van.
      expect(await ontleedCatalogus(Uint8List.fromList(utf8.encode('geen json'))), isNull);
      expect(await ontleedCatalogus(Uint8List(0)), isNull);
    });

    test('geldige JSON die geen kaart is telt niet als bibliotheek', () async {
      expect(await ontleedCatalogus(Uint8List.fromList(utf8.encode('[1,2,3]'))), isNull);
    });
  });

  group('DE KERN: de kopie wordt niet terugcodeerd', () {
    late Directory scratch;
    late CatalogusKopie kopie;

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('dm_catbytes_');
      setAppDirForTest(scratch.path);
      kopie = const CatalogusKopie();
    });

    tearDown(() {
      try {
        scratch.deleteSync(recursive: true);
      } on FileSystemException {/* een achtergebleven map is geen gezakte toets waard */}
    });

    test('de bytes van de pc gaan erin en dezelfde inhoud komt eruit', () async {
      final vanDePc = {
        'albums': [
          {'id': 'a1', 'title': 'Whigfield'}
        ]
      };
      await kopie.bewaarBytes(_bytes(vanDePc));
      final terug = await kopie.lees();
      expect(terug, isNotNull);
      expect(terug!.json['albums'], vanDePc['albums']);
    });

    test('een lege lijst bytes schrijft niets', () async {
      // Anders vervangt een mislukte poging een goede kopie door een leeg bestand, en dan staat er
      // bij de volgende start niets terwijl er iets stond.
      await kopie.bewaarBytes(_bytes({'albums': const []}));
      await kopie.bewaarBytes(const []);
      expect(await kopie.lees(), isNotNull, reason: 'de oude kopie hoort te blijven staan');
    });

    test('een tweede keer bewaren vervangt de eerste', () async {
      await kopie.bewaarBytes(_bytes({'albums': const []}));
      await kopie.bewaarBytes(_bytes({
        'albums': [
          {'id': 'a2', 'title': 'Later'}
        ]
      }));
      final terug = await kopie.lees();
      expect((terug!.json['albums'] as List).length, 1);
    });
  });
}
