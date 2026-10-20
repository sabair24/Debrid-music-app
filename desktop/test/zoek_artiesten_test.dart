// De rij "Artiesten" in Online zoeken (zoek_artiesten.dart). Saber, 20-10-2026, bij "Chappell Roan Good
// Luck Babe": "waarom zijn er geen afbeeldingen bij artist?" — Deezer vond geen artiest op de hele zin,
// MusicBrainz vulde aan met "Good Luck", "BaBe", "Roan" en een Chappell Roan zonder foto.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/zoek_artiesten.dart';

void main() {
  CatalogTrackHit nummer(String titel, String artiest, {int? id, String? foto}) =>
      CatalogTrackHit(titel, artiest, null, artistId: id, artistPicture: foto);

  group('de artiestenrij', () {
    test('geen artiest op de hele zin: de artiest van de gevonden nummers, met zijn foto', () {
      final rij = artiestenVoorZoekrij(const [], [
        nummer('Good Luck, Babe!', 'Chappell Roan', id: 12945219, foto: 'https://cdn/chappell.jpg'),
        nummer('Good Luck, Babe! (Piano)', 'Capybara Piano', id: 7, foto: 'https://cdn/piano.jpg'),
      ], 'Chappell Roan Good Luck Babe');
      expect(rij.map((a) => a.name), ['Chappell Roan', 'Capybara Piano']);
      expect(rij.first.id, 12945219);
      expect(rij.first.picture, 'https://cdn/chappell.jpg');
    });

    test('wie precies zo heet als de zoekzin gaat voor; elke artiest één keer', () {
      final rij = artiestenVoorZoekrij(const [
        CatalogArtist(1, 'Hello I\'m Adele', 'x', 3),
        CatalogArtist(2, 'Adele', 'https://cdn/adele.jpg', 20),
      ], [
        nummer('Hello', 'Adele', id: 2, foto: 'https://cdn/adele.jpg'),
        nummer('Hello (Cover)', 'Wellhello', id: 9),
      ], 'Adele');
      expect(rij.map((a) => a.name), ['Adele', 'Wellhello', 'Hello I\'m Adele']);
    });

    test('hoogstens drie uit de nummers, en een nummer zonder Deezer-artiest telt niet', () {
      final rij = artiestenVoorZoekrij(const [], [
        nummer('a', 'Een', id: 1),
        nummer('b', '', id: 2),
        nummer('c', 'Twee'),
        nummer('d', 'Drie', id: 3),
        nummer('e', 'Een', id: 1),
        nummer('f', 'Vier', id: 4),
        nummer('g', 'Vijf', id: 5),
      ], 'iets');
      expect(rij.map((a) => a.name), ['Een', 'Drie', 'Vier']);
    });
  });

  group('MusicBrainz in de rij', () {
    test('alleen wie de zoekzin begint, op een woordgrens', () {
      const zin = 'Chappell Roan Good Luck Babe';
      expect(mbArtiestPastBijZoekzin(zin, 'Chappell Roan'), isTrue);
      expect(mbArtiestPastBijZoekzin(zin, 'Good Luck'), isFalse);
      expect(mbArtiestPastBijZoekzin(zin, 'BaBe'), isFalse);
      expect(mbArtiestPastBijZoekzin(zin, 'Roan'), isFalse);
      expect(mbArtiestPastBijZoekzin(zin, 'Chappell'), isTrue, reason: 'een woordgrens');
      expect(mbArtiestPastBijZoekzin(zin, 'Chap'), isFalse, reason: 'geen half woord');
      expect(mbArtiestPastBijZoekzin('The Doors', 'Doors'), isTrue, reason: 'zoals artistKey: "the" telt niet');
      expect(mbArtiestPastBijZoekzin('Sabien Tiels', 'Sabien Tiels'), isTrue, reason: 'een artiest die Deezer niet kent');
    });

    test('de foto uit TheAudioDB: de miniatuur, anders een brede, anders niets', () {
      expect(audioDbFotoUit({'artists': [{'strArtistThumb': 'https://r2.theaudiodb.com/a.jpg'}]}),
          'https://r2.theaudiodb.com/a.jpg');
      expect(audioDbFotoUit({'artists': [{'strArtistThumb': null, 'strArtistWideThumb': 'https://w.jpg'}]}), 'https://w.jpg');
      expect(audioDbFotoUit({'artists': null}), isNull, reason: 'onbekend bij TheAudioDB');
      expect(audioDbFotoUit('rommel'), isNull);
    });

    test('de foto uit Discogs: de hoofdfoto, anders de eerste', () {
      expect(discogsFotoUit(const []), isNull);
      expect(
          discogsFotoUit(const [
            DiscogsImage('https://i.discogs.com/een.jpg', '', 600, 600, false),
            DiscogsImage('https://i.discogs.com/hoofd.jpg', '', 600, 600, true),
          ]),
          'https://i.discogs.com/hoofd.jpg');
      expect(discogsFotoUit(const [DiscogsImage('https://i.discogs.com/een.jpg', '', 600, 600, false)]),
          'https://i.discogs.com/een.jpg');
    });

    test('de Discogs-sleutel gaat alleen naar Discogs, ook bij een plaatje dat het scherm laadt', () {
      final instellingen = AppSettings()..discogsToken = 'geheim';
      final d = DiscogsService(instellingen);
      expect(d.beeldKoppen('https://i.discogs.com/a.jpg')['Authorization'], 'Discogs token=geheim');
      expect(d.beeldKoppen('https://r2.theaudiodb.com/a.jpg').containsKey('Authorization'), isFalse);
      expect(d.beeldKoppen('https://upload.wikimedia.org/a.jpg').containsKey('Authorization'), isFalse);
    });

    test('aangesloten: rij, filter en het vangnet op het MusicBrainz-nummer — nooit op naam', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('_artists = artiestenVoorZoekrij(res[0] as List<CatalogArtist>, _trackHits, q);'));
      expect(main, contains('if (mbArtiestPastBijZoekzin(q, a.name) && have.add(artistKey(a.name)))'));
      expect(main, contains('future: MbArtiestFoto.voor(a.origin!.id, context.read<MusicBrainzService>(),'));
      expect(main, contains('headers: s.data == null ? null : discogs.beeldKoppen(s.data!)),'));
      final bron = File('lib/zoek_artiesten.dart').readAsStringSync();
      expect(bron, contains("artist-mb.php?i="), reason: 'TheAudioDB op het nummer, niet search.php?s=');
      expect(bron, isNot(contains('search.php?s=')));
      expect(bron, contains('final id = await mb.discogsArtistId(mbid);'), reason: 'Discogs op het nummer: Oasis');
      expect(bron, contains("(await discogs.artist('', id: id))"));
      expect(bron, contains('final q = await mb.wikidataId(mbid);'));
      expect(bron.indexOf('_audioDb(mbid)'), lessThan(bron.indexOf('discogsArtistId(mbid)')));
      expect(bron.indexOf('discogsArtistId(mbid)'), lessThan(bron.indexOf('wikidataId(mbid)')));
      final catalog = File('lib/catalog.dart').readAsStringSync();
      expect(RegExp(r"artistId: \(t\['artist'\]\?\['id'\] as num\?\)\?\.toInt\(\),").allMatches(catalog).length, 2,
          reason: 'zoeken én de hitlijst dragen de artiest mee');
    });
  });
}
