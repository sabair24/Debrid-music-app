// De achterkant en de cd die al binnenkwamen en werden weggegooid.
//
// TheAudioDB houdt per album strAlbumBack en strAlbumCDart bij. Live nagemeten op Rihanna / ANTI:
// beide gevuld. En de app haalde dat antwoord al op bij élke pagina-opening -- voor de tekst -- en
// las alleen de tekstvelden.
//
// Waarom dat uitmaakt: de Cover Art Archive heeft voor de meeste persingen geen scans, en de terugval
// daarna is Discogs, met zestig verzoeken per minuut als schaarste. In warm.log van de echte
// bibliotheek stond één album twee minuten op zijn beurt te wachten. TheAudioDB kost geen sleutel en
// geen budget.
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/enrichment.dart';

void main() {
  test('de twee url-velden overleven de schijfcache', () {
    const info = AlbumInfo(
      description: 'iets',
      backUrl: 'https://r2.theaudiodb.com/images/media/album/back/qqxsqy1488398368.jpg',
      discUrl: 'https://r2.theaudiodb.com/images/media/album/cdart/rqqvrq1589808032.png',
    );
    final terug = AlbumInfo.fromJson(info.toJson());
    expect(terug.backUrl, info.backUrl);
    expect(terug.discUrl, info.discUrl);
    expect(terug.description, 'iets');
  });

  test('een album dat alleen scans heeft is niet leeg', () {
    // isEmpty besliste of het antwoord bewaard wordt. Zonder deze twee erbij zou een album met een
    // achterkant en een cd maar zonder omschrijving worden weggegooid -- precies het geval waar dit
    // voor bedoeld is.
    const alleenScans = AlbumInfo(
      backUrl: 'https://example.invalid/back.jpg',
      discUrl: 'https://example.invalid/cd.png',
    );
    expect(alleenScans.isEmpty, isFalse);
  });

  test('leeg blijft leeg', () {
    expect(const AlbumInfo().isEmpty, isTrue);
  });

  test('ontbrekende url-velden komen als null terug, niet als de tekst "null"', () {
    final terug = AlbumInfo.fromJson({'description': 'x'});
    expect(terug.backUrl, isNull);
    expect(terug.discUrl, isNull);
  });
}
