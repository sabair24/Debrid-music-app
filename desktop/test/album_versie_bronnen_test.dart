/// "(Album Version)" is de gewone plaatopname, geen andere uitvoering — en mag dus geen enkele bron
/// kosten. Gemeld op 15-10-2026 met een schermafdruk: op een album van Marc Lavoine kregen precies de
/// nummers met "(Album Version)" in de titel nul bronnen, die zonder 21 tot 41.
///
/// Wat óók vastligt: de lengte blijft de grens. Saber, zelfde ochtend: "wel letten dat het de juiste
/// zijn, door de officiële speeltijd zo precies mogelijk te vergelijken". Een nummer zonder merk in de
/// naam maar met een andere lengte (een radio-edit, een live-opname) valt nog altijd af, en een echt
/// merk ("(Radio Edit)", "(Live)") ook.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/organize.dart';

const _artiest = 'Marc Lavoine';
const _map = r'@@peer\Music\Marc Lavoine\2001 - Marc Lavoine\';

bool biedt(String titel, String bestand, {int officieel = 223, int? lengte = 223, String? album}) =>
    fileOffersTitle(titel, officieel, _artiest, '$_map$bestand', lengte, album: album);

void main() {
  test('"(Album Version)" in de titel, kaal in het bestand: dezelfde opname', () {
    expect(biedt('Passent Les Nuages (Album Version)', '02 - Passent les nuages.flac'), isTrue);
    expect(biedt('Passent Les Nuages (Album Version)', 'Marc Lavoine - Passent les nuages.flac'), isTrue);
    expect(biedt('Passent Les Nuages (Album Version)', '02 - Passent les nuages.flac', album: 'Marc Lavoine'), isTrue);
  });

  test('en andersom: het merk in de bestandsnaam, kaal in de catalogus', () {
    expect(biedt('Passent Les Nuages', '02 Passent les nuages (Album Version).flac'), isTrue);
    expect(biedt('Passent Les Nuages', '02 Passent les nuages (Album Mix).flac'), isTrue);
    expect(biedt('Gimme More (Main Version)', '01 Gimme More.flac'), isTrue);
  });

  test('de lengte blijft de grens: buiten 12 s geen bron, ook niet met een passende titel', () {
    expect(biedt('Passent Les Nuages (Album Version)', '02 - Passent les nuages.flac', lengte: 223 + 13), isFalse);
    expect(biedt('Passent Les Nuages (Album Version)', '02 - Passent les nuages.flac', lengte: 223 - 30), isFalse,
        reason: 'een radio-edit zonder merk in de naam is 30 s korter');
    expect(biedt('Passent Les Nuages (Album Version)', '02 - Passent les nuages.flac', lengte: 223 + 2), isTrue);
  });

  test('een echt merk blijft een andere opname', () {
    expect(biedt('Passent Les Nuages (Album Version)', '02 - Passent les nuages (Radio Edit).flac'), isFalse);
    expect(biedt('Passent Les Nuages (Album Version)', '02 - Passent les nuages (Live).flac'), isFalse);
    expect(biedt('Passent Les Nuages (Live)', '02 - Passent les nuages.flac'), isFalse);
    expect(biedt('Passent Les Nuages (Album Version) (Live)', '02 - Passent les nuages.flac'), isFalse,
        reason: 'naast een echt merk wordt niets weggehaald');
  });

  // Hieronder: gemeten over de eigen bibliotheek (15-10-2026, 117 nummers waarvan de gevraagde versie in
  // de map stond). Voor: 99 aanvaard; na: 109, en nul keer een bestand voor een andere versie.
  group('een remix of live-versie die je wil, wordt gevonden', () {
    test('merk in titel, map én bestandsnaam', () {
      expect(
          fileOffersTitle('MORNING DEW (DONK MIX)', null, 'Beyoncé',
              r'@@p\Beyoncé\MORNING DEW (DONK) REMIX PACK\02 - MORNING DEW (DONK MIX).flac', null,
              album: 'MORNING DEW (DONK) REMIX PACK'),
          isTrue);
    });

    test('een gastartiest in de bestandsnaam', () {
      expect(
          fileOffersTitle('Scream Louder (Flyte Tyme remix)', null, 'Michael Jackson',
              r'@@p\Michael Jackson\06 - Scream Louder (Flyte Tyme Remix) (feat. Janet Jackson).flac', null),
          isTrue);
      expect(
          fileOffersTitle('Hold on to the Vision (original mix)', null, 'Frank Harris',
              r"@@p\Frank Harris\01. Frank Harris – 'Hold On To The Vision' Original Mix (featuring Joe Satriani on Guitar).flac", null),
          isTrue);
    });

    test('puntjes in een afkorting, een schijfnummer, een lang volgnummer', () {
      expect(fileOffersTitle('Oceans (U.H.T. Radio Mix)', null, 'Morimor', r'@@p\x\2. Oceans (UHT Radio Mix).flac', null), isTrue);
      expect(
          fileOffersTitle('Te Quiero (Paul Kalkbrenner Remix)', null, 'Stromae',
              r'@@p\x\15 Stromae - CD-01 - Te quiero (Paul Kalkbrenner remix).flac', null),
          isTrue);
      expect(
          fileOffersTitle('Take Me for a Ride (radio mix)', null, 'Alana Dante',
              r'@@p\x\3586. Alana Dante - Take Me For A Ride (Radio Mix).flac', null),
          isTrue);
    });

    test('een deel: "Part II" is "Pt. 2", en een ander deel is een ander nummer', () {
      expect(
          fileOffersTitle('Love the Way You Lie (Part II)', null, 'Rihanna', r'@@p\x\11 - Love the Way You Lie, Pt. 2 (part 2).flac', null),
          isTrue);
      expect(fileOffersTitle('Confessions Part II', null, 'Usher', r'@@p\x\05 - Confessions, Part 2.flac', null), isTrue);
      expect(fileOffersTitle('Love in This Club, Part 2', null, 'Usher', r'@@p\x\02 - Love in This Club.flac', null), isFalse,
          reason: 'deel 2 is een ander nummer dan het gewone');
      expect(fileOffersTitle('Love in This Club', null, 'Usher', r'@@p\x\02 - Love in This Club.flac', null), isTrue);
      expect(fileOffersTitle('Love in This Club, Part 2', null, 'Usher', r'@@p\x\12 - Love in This Club, Part II.flac', null),
          isTrue);
      expect(fileOffersTitle('Confessions', null, 'Usher', r'@@p\x\05 - Confessions, Part 2.flac', null), isFalse);
    });

    test('een andere mix blijft een andere mix, ook met een gastartiest erbij', () {
      expect(
          fileOffersTitle('Levels (Skrillex Remix)', null, 'Avicii', r'@@p\x\01 - Levels (Radio Version).flac', null),
          isFalse);
      expect(
          fileOffersTitle('Scream Louder (Flyte Tyme remix)', null, 'Michael Jackson',
              r'@@p\x\06 - Scream Louder (feat. Janet Jackson).flac', null),
          isFalse,
          reason: 'de gast weg, en dan blijft het gewone nummer over: geen remix');
      expect(fileOffersTitle('Song (with Strings)', null, 'X', r'@@p\x\01 - Song.flac', null), isFalse,
          reason: '"with" is geen gast: met strijkers is een andere uitvoering');
      expect(fileOffersTitle('Song (Club Mix)', null, 'X', r'@@p\x\01 - Song (Club Mix) (with Strings).flac', null), isFalse,
          reason: 'ook in de bestandsnaam is "(with …)" geen gast die weg mag');
      expect(fileOffersTitle('Easy On Me', 224, 'Adele', r'@@p\x\01 - Easy On Me (feat. Chris Stapleton).flac', 224), isFalse,
          reason: 'bij een kale titel kan de gast het verschil zijn: het duet is niet het solonummer');
    });
  });

  test('een ander nummer blijft een ander nummer', () {
    expect(biedt('Passent Les Nuages (Album Version)', '03 - J\'aurais voulu.flac'), isFalse);
  });
}
