// Een WAV wordt niet meer aangeboden om te downloaden.
//
// Een WAV kan de tags die deze app schrijft niet dragen: stampTags weigert alles behalve FLAC, en de
// RIFF-writer van de dependency herschrijft alleen een LIST/INFO-chunk die er AL staat -- hij voegt er
// nooit een toe. Nagemeten op de zes die hier waren geland: alle zes hadden niets dan `fmt` en `data`,
// dus de bibliotheek las geen artiest, geen album en geen titel, en zette elk als naamloze single
// onder "Onbekende artiest".
//
// Laag ranken was niet genoeg. Was er geen FLAC in de aanbieding, dan won een WAV alsnog -- en won een
// kopie die de app nooit kon labelen.
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/soulseek.dart';

SoulseekFile f(String naam, {int size = 30000000, bool freeSlots = true, int speed = 500}) =>
    SoulseekFile(
      username: 'iemand',
      filename: 'C:\\muziek\\$naam',
      size: size,
      speed: speed,
      queueLength: 0,
      freeSlots: freeSlots,
    );

void main() {
  test('een WAV komt niet in de kandidatenlijst', () {
    final uit = sortSoulseek([f('01 - Nummer.wav'), f('01 - Nummer.flac')]);
    expect(uit.map((x) => x.ext), ['flac']);
  });

  test('ook niet als hij de ENIGE aanbieding is', () {
    // Dit was het gat: laag ranken hielp niet als er niets anders was.
    expect(sortSoulseek([f('01 - Nummer.wav')]), isEmpty);
  });

  test('ook niet als hij groter en sneller is', () {
    final uit = sortSoulseek([
      f('groot.wav', size: 90000000, speed: 9000),
      f('klein.mp3', size: 8000000, speed: 100),
    ]);
    expect(uit.map((x) => x.ext), ['mp3']);
  });

  test('WAV in hoofdletters ook niet', () {
    expect(sortSoulseek([f('01 - Nummer.WAV')]), isEmpty);
  });

  test('de andere formaten blijven en houden hun volgorde', () {
    final uit = sortSoulseek([
      f('c.mp3'),
      f('a.flac'),
      f('b.wav'),
      f('d.m4a'),
    ]);
    expect(uit.first.ext, 'flac', reason: 'FLAC wint nog steeds');
    expect(uit.map((x) => x.ext), isNot(contains('wav')));
    expect(uit, hasLength(3));
  });

  test('niet-audio blijft ook geweerd', () {
    final uit = sortSoulseek([f('hoes.jpg'), f('lees.nfo'), f('a.flac')]);
    expect(uit.map((x) => x.ext), ['flac']);
  });

  test('isAudio zegt nog wel dat een WAV audio IS', () {
    // Belangrijk onderscheid: wat er op schijf staat moet blijven spelen en meetellen. Dit gaat
    // alleen over wat er wordt aangeboden.
    expect(f('a.wav').isAudio, isTrue);
  });
}
