/// De hoes op het scherm hoort bij het nummer dat klinkt.
///
/// Aanleiding: casten van de Mac naar de Sonos Amp. De titel en de artiest liepen keurig mee met de
/// speaker, maar de hoes -- en daarmee ook de wazige achtergrond en de mini-balk -- bleef staan op
/// het album waarmee de overdracht begon. Op het nu-speelt-scherm stond Whitney Houston boven "The
/// Girl Is Mine" van Michael Jackson, met de cd van Thriller ernaast.
///
/// De oorzaak was één hergebruikte helper. `followSpeaker` riep `refreshCover` aan, en die is
/// gebouwd voor een heel andere vraag: "dezelfde plaat, is de hoes intussen gecorrigeerd?" Daar is
/// een leeg antwoord terecht geen antwoord. Voor een ANDER nummer betekent datzelfde lege antwoord
/// dat de hoes die er staat bij een album hoort dat niet meer speelt.
///
/// [PlayerStore] is niet te construeren in een test -- die bouwt een libmpv-speler in een veld -- dus
/// de regel staat als losse functie in player.dart, net als `ordenVoor`.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/player.dart';

void main() {
  final whitney = Uint8List.fromList([1, 1, 1]);
  final thriller = Uint8List.fromList([2, 2, 2]);

  group('hoesOpScherm', () {
    test('dezelfde plaat: een leeg antwoord laat de hoes staan', () {
      // De bibliotheek hergroepeert; de hoes die dit album krijgt is nog niet bekend. De balk
      // blanco maken zou hier een flikkering zijn, geen verbetering.
      expect(hoesOpScherm(whitney, null, zelfdeNummer: true), same(whitney));
    });

    test('dezelfde plaat: een gecorrigeerde hoes wint', () {
      expect(hoesOpScherm(whitney, thriller, zelfdeNummer: true), same(thriller));
    });

    test('de speaker schuift door: een leeg antwoord wist de hoes', () {
      // Dit is de regressie. Blijft hier `whitney` staan, dan toont het scherm een album dat niet
      // speelt -- en dat blijft zo voor de rest van de wachtrij, want elk volgend nummer stelt
      // dezelfde vraag opnieuw.
      expect(hoesOpScherm(whitney, null, zelfdeNummer: false), isNull);
    });

    test('de speaker schuift door: de hoes van het nieuwe album wint', () {
      expect(hoesOpScherm(whitney, thriller, zelfdeNummer: false), same(thriller));
    });

    test('niets bekend blijft niets, in beide gevallen', () {
      expect(hoesOpScherm(null, null, zelfdeNummer: true), isNull);
      expect(hoesOpScherm(null, null, zelfdeNummer: false), isNull);
    });
  });
}
