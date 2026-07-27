// Twee bestanden van hetzelfde nummer in één album herkennen.
//
// Gemeten op de echte Backstreet's Back: nummer 10 stond er twee keer, als 35 MB (encoder=Lavf, een
// omzetting) en als 49 MB (Source=CD (Lossless)), allebei 4:50. Ze heetten net iets anders omdat ze
// tegen twee verschillende persingen waren gelegd, en de opruimer vergelijkt op naam -- dus bleven
// ze allebei staan.
//
// De valkuil zit in de voor de hand liggende oplossing. Op diezelfde plaat liggen tien paren binnen
// de twaalf seconden speling van elkaar (4:23 naast 4:25, 3:30 naast 3:33); op looptijd alleen zou
// het halve album als dubbel worden aangewezen.
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/completeness.dart';
import 'package:debridmusic/models.dart';

Track t(String path, String title, int secs) => Track(
      path: path,
      title: title,
      artist: 'Backstreet Boys',
      album: "Backstreet's Back",
      duration: Duration(seconds: secs),
      isFlac: true,
    );

/// De winnaar wordt hier meegegeven, zodat dit deel zonder schijf te testen is.
List<SameRecordingPair> vind(List<Track> ts, {Set<String> wint = const {}}) => sameRecordingPairs(
      ts,
      better: (a, b) => wint.contains(a.path),
      why: (k, d) => 'test',
    );

void main() {
  test('twee schrijfwijzen van hetzelfde nummer, even lang: één paar', () {
    final a = t('a.flac', 'If You Want It to Be Good Girl (Get Yourself a Bad Boy)', 290);
    final b = t('b.flac', 'If You Want to Be a Good Girl (Get Yourself a Bad Boy)', 290);
    final r = vind([a, b], wint: {'a.flac'});
    expect(r, hasLength(1));
    expect(r.single.keep.path, 'a.flac');
    expect(r.single.drop.path, 'b.flac');
  });

  test('de echte plaat levert precies dat ene paar op, niet het halve album', () {
    // De looptijden zoals ze op schijf staan. Tien paren liggen binnen twaalf seconden.
    final plaat = [
      t('01.flac', "Everybody (Backstreet's Back)", 227),
      t('02.flac', 'As Long as You Love Me', 213),
      t('03.flac', 'All I Have to Give', 274),
      t('04.flac', 'Missing You', 263),
      t('05.flac', "That's the Way I Like It", 219),
      t('06.flac', '10,000 Promises', 243),
      t('07.flac', 'Like a Child', 305),
      t('08.flac', "Hey, Mr. DJ (Keep Playin' This Song)", 265),
      t('09.flac', 'Set Adrift on Memory Bliss', 210),
      t('10.flac', "That's What She Said", 244),
      t('11.flac', 'If You Want It to Be Good Girl (Get Yourself a Bad Boy)', 290),
      t('11b.flac', 'If You Want to Be a Good Girl (Get Yourself a Bad Boy)', 290),
      t('13.flac', "If I Don't Have You", 274),
    ];
    final r = vind(plaat, wint: {'11.flac'});
    expect(r, hasLength(1), reason: 'alleen de dubbele, ondanks tien paren van gelijke lengte');
    expect(r.single.drop.path, '11b.flac');
  });

  test('twee verschillende nummers van gelijke lengte zijn geen paar', () {
    // Allebei 4:34, en allebei echt aanwezig op deze plaat.
    final r = vind([
      t('03.flac', 'All I Have to Give', 274),
      t('13.flac', "If I Don't Have You", 274),
    ]);
    expect(r, isEmpty);
  });

  test('een radio-edit naast de albumversie blijft met rust', () {
    // Zelfde titel, zelfde lengte, maar de ene draagt een versiemarkering: twee opnames.
    final r = vind([
      t('a.flac', 'Everybody', 227),
      t('b.flac', 'Everybody (Radio Edit)', 227),
    ]);
    expect(r, isEmpty, reason: 'sameTitle weigert dit op de markering, en terecht');
  });

  test('zelfde titel maar echt andere lengte is geen paar', () {
    final r = vind([
      t('a.flac', 'Missing You', 263),
      t('b.flac', 'Missing You', 400),
    ]);
    expect(r, isEmpty, reason: 'buiten de speling — een andere opname of een andere mix');
  });

  test('een bestand zonder looptijd wordt nooit weggegooid op de titel alleen', () {
    final r = vind([
      Track(path: 'a.flac', title: 'Missing You', artist: 'BSB', album: 'X', isFlac: true),
      t('b.flac', 'Missing You', 263),
    ]);
    expect(r, isEmpty, reason: 'geen lengte, geen bewijs');
  });

  test('drie kopieën leveren één paar per ronde', () {
    final r = vind([
      t('a.flac', 'Missing You', 263),
      t('b.flac', 'Missing You', 263),
      t('c.flac', 'Missing You', 263),
    ], wint: {'a.flac'});
    expect(r, hasLength(1), reason: 'a en b; c komt de volgende keer aan de beurt');
  });

  test('een album zonder dubbelen meldt niets', () {
    final r = vind([
      t('01.flac', 'Everybody', 227),
      t('02.flac', 'As Long as You Love Me', 213),
    ]);
    expect(r, isEmpty);
  });
}
