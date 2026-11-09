import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/discography.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/recommend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Saber, 09-11-2026: "waarom vindt ik meer resultaten bij doo wop single, dan op de album ??" en "daarom mis ik wel heel veel
/// resultaten". De echte heet bij Deezer en MusicBrainz "Ms. Lauryn Hill"; onder "Lauryn Hill" staat een christelijke zangeres.
/// En de plaat opende op een promo-sampler met 7 nummers. De getallen hieronder zijn de echte antwoorden.
const deezerHits = [
  {'id': 127408692, 'name': 'Lauryn Hill', 'nb_fan': 1775, 'nb_album': 2},
  {'id': 1117, 'name': 'Ms. Lauryn Hill', 'nb_fan': 557606, 'nb_album': 8},
  {'id': 5511926, 'name': 'Lauryn Hill & Bob Marley', 'nb_fan': 147, 'nb_album': 0},
];

void main() {
  // MusicBrainz bewaart zijn antwoorden: niet in de echte appmap, en niet over twee toetsen heen.
  setUpAll(() => setAppDirForTest(Directory.systemTemp.createTempSync('aanspreking').path));

  group('dezelfde met een aanspreking', () {
    test('Ms., Mrs., Mr. en Miss wel; DJ, een achternaam of een band niet', () {
      expect(isAansprekingVan('Ms. Lauryn Hill', 'Lauryn Hill'), isTrue);
      expect(isAansprekingVan('Mr. Oizo', 'Oizo'), isTrue);
      expect(isAansprekingVan('Miss Kittin', 'Kittin'), isTrue);
      expect(isAansprekingVan('DJ Khaled', 'Khaled'), isFalse);
      expect(isAansprekingVan('Pink Floyd', 'Pink'), isFalse);
      expect(isAansprekingVan('Lauryn Hill', 'Lauryn Hill'), isFalse);
      expect(isAansprekingVan('Ms.', ''), isFalse);
    });

    test('aanbevelingen: de echte, ook al is de naam niet exact', () {
      expect(pickArtist(deezerHits, 'Lauryn Hill'), 1117);
    });

    test('een exacte naam met eigen publiek blijft staan', () {
      const hits = [
        {'id': 1, 'name': 'Oizo', 'nb_fan': 1000},
        {'id': 2, 'name': 'Mr. Oizo', 'nb_fan': 15000},
      ];
      expect(pickArtist(hits, 'Oizo'), 1, reason: 'vijftien keer is geen bewijs; bij Lauryn Hill is het 314 keer');
    });

    test('Khaled blijft Khaled, ook al heeft DJ Khaled meer fans', () {
      const hits = [
        {'id': 5828, 'name': 'DJ Khaled', 'nb_fan': 1687714},
        {'id': 75354, 'name': 'Khaled', 'nb_fan': 712913},
      ];
      expect(pickArtist(hits, 'Khaled'), 75354);
    });

    test('Deezer: zoeken op artiest zet de echte vooraan', () async {
      final uit = await http.runWithClient(
        () => CatalogService().searchArtists('Lauryn Hill'),
        () => MockClient((_) async => http.Response(jsonEncode({'data': deezerHits}), 200)),
      );
      expect(uit.first.id, 1117);
      expect(uit[1].id, 127408692, reason: 'de naamgenoot blijft te vinden');
    });

    test('Deezer: een exacte naam met eigen publiek blijft vooraan', () async {
      final uit = await http.runWithClient(
        () => CatalogService().searchArtists('Oizo'),
        () => MockClient((_) async => http.Response(
            jsonEncode({
              'data': [
                {'id': 2, 'name': 'Mr. Oizo', 'nb_fan': 15000},
                {'id': 1, 'name': 'Oizo', 'nb_fan': 1000},
              ]
            }),
            200)),
      );
      expect(uit.first.id, 1);
    });

    group('MusicBrainz, dat geen fans kent: wie de meeste platen heeft', () {
      Future<MbArtist?> vraag(int exact, int metAanspreking,
              {String naam = 'Lauryn Hill', String echte = 'e8414012', String andere = 'b14191fa'}) =>
          http.runWithClient(
            () => MusicBrainzService().resolveArtist(naam),
            () => MockClient((r) async {
              final u = r.url.toString();
              if (u.contains('/artist/')) {
                return http.Response(
                    jsonEncode({
                      'artists': [
                        {'id': andere, 'name': naam, 'score': 100, 'disambiguation': 'Christian singer'},
                        {'id': echte, 'name': 'Ms. $naam', 'score': 98},
                      ]
                    }),
                    200);
              }
              return http.Response(jsonEncode({'release-group-count': u.contains(echte) ? metAanspreking : exact}), 200);
            }),
          );

      test('Lauryn Hill: de echte', () async {
        expect((await vraag(1, 12))?.mbid, 'e8414012');
      }, timeout: const Timeout(Duration(seconds: 30)));

      test('heeft de exacte naam evenveel of meer: die', () async {
        expect((await vraag(12, 12, naam: 'Iemand Anders', echte: 'echte-2', andere: 'andere-2'))?.mbid, 'andere-2');
      }, timeout: const Timeout(Duration(seconds: 30)));
    });

    test('de discografie telt de naam met aanspreking als dezelfde', () {
      final bron = File('lib/discography_service.dart').readAsStringSync();
      expect(bron, contains('artistKey(gevraagd) == artistKey(gevonden) || isAansprekingVan(gevonden, gevraagd);'));
    });
  });

  group('een promo is niet de plaat', () {
    DiscoRelease rij(RecordKind kind, CatalogRef ref) => DiscoRelease(
          title: 'The Miseducation Of Lauryn Hill',
          kind: kind,
          firstDate: '1998',
          sources: const {DiscoSource.discogs},
          refs: {DiscoSource.discogs: ref},
        );

    final sampler = rij(RecordKind.other, CatalogRef.discogsRelease(5891520));
    final master = rij(RecordKind.album, CatalogRef.discogsMaster(57279));

    test('DE KERN: de sampler kwam eerst, en toch opent de regel op het master', () {
      final uit = mergeDiscography([
        [sampler, master]
      ]);
      expect(uit, hasLength(1));
      expect(uit.single.openRef?.source, CatalogSource.discogsMaster);
      expect(uit.single.openRef?.id, '57279');
    });

    test('in beide volgordes', () {
      expect(master.mergedWith(sampler).openRef?.id, '57279');
      expect(sampler.mergedWith(master).openRef?.id, '57279');
    });

    test('twee persingen: die van een album wint van die zonder oordeel', () {
      final album = rij(RecordKind.album, CatalogRef.discogsRelease(244851));
      expect(sampler.mergedWith(album).openRef?.id, '244851');
      expect(album.mergedWith(sampler).openRef?.id, '244851');
    });

    test('Deezer gaat nog altijd voor: die geeft de tracklijst in één vraag', () {
      final deezer = DiscoRelease(
        title: 'The Miseducation of Lauryn Hill',
        kind: RecordKind.album,
        firstDate: '1998',
        sources: const {DiscoSource.deezer},
        refs: {DiscoSource.deezer: CatalogRef.deezer(1440802)},
      );
      expect(master.mergedWith(deezer).openRef?.source, CatalogSource.deezer);
    });

    test('Discogs schrijft het op twee manieren', () {
      expect(isSamplerFormaat('CD, Promo, Smplr'), isTrue);
      expect(isSamplerFormaat('Album, Promo, Sampler'), isTrue);
      expect(isPromoFormaat('CD, Promo, Smplr'), isTrue);
      expect(isPromoFormaat('Album'), isFalse);
      expect(isSamplerFormaat('CD, Album'), isFalse);
      expect(isPromoFormaat('Promotional Poster'), isFalse, reason: 'op velden, niet op deelreeksen');
    });

    test('bij de persingen van een plaat staan promo en sampler achteraan', () {
      const promo = DiscogsVersion(1180247, 'Album, Promo, Sampler', 'CD', 'Columbia', 'X', 'Europe', '1998');
      const echt = DiscogsVersion(244851, 'Album, Stereo', 'CD', 'Ruffhouse', 'Y', 'US', '1998');
      expect(DiscogsService.orderByPreference(const [promo, echt]).first.id, 244851);
      expect(DiscogsService.orderByPreference(const [promo, echt], main: 1180247).first.id, 244851,
          reason: 'ook als Discogs de promo de hoofduitgave noemt');
    });

    test('een sampler als losse persing komt de discografie niet in', () {
      final bron = File('lib/discogs.dart').readAsStringSync();
      expect(bron, contains('if (!master && isSamplerFormaat(formaat)) continue;'));
    });
  });
}
