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

  test('een ander nummer blijft een ander nummer', () {
    expect(biedt('Passent Les Nuages (Album Version)', '03 - J\'aurais voulu.flac'), isFalse);
  });
}
