// Saber, 19-10-2026: "vaak merk ik dat er singles staan bij albums, bij veel artiesten". Een album en
// de single met dezelfde titel werden op titel alleen één regel, en die droeg dan de hoes, de nummers
// en de link van de single. GEMETEN over negen artiesten (singles_bij_albums_live_test): 9 van de 192
// albumtegels openden op een single of EP; na deze regels 0.
import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/discography.dart';
import 'package:flutter_test/flutter_test.dart';

DiscoRelease _dz(String titel, RecordKind soort, int id, String datum) => DiscoRelease(
      title: titel,
      kind: soort,
      firstDate: datum,
      cover: 'https://dz/$id.jpg',
      sources: const {DiscoSource.deezer},
      refs: {DiscoSource.deezer: CatalogRef.deezer(id)},
    );

DiscoRelease _mb(String titel, RecordKind soort, String datum) => DiscoRelease(
      title: titel,
      kind: soort,
      firstDate: datum,
      sources: const {DiscoSource.musicbrainz},
      refs: {DiscoSource.musicbrainz: CatalogRef.musicbrainzGroup('mb-$titel-${soort.name}')},
    );

DiscoRelease _dg(String titel, RecordKind soort, int id, String datum) => DiscoRelease(
      title: titel,
      kind: soort,
      firstDate: datum,
      sources: const {DiscoSource.discogs},
      refs: {DiscoSource.discogs: CatalogRef.discogsRelease(id)},
    );

void main() {
  group('samenvoegen', () {
    test('DE KERN: album en single met dezelfde titel bij Deezer zijn twee regels, elk met zijn eigen link', () {
      // Céline Dion: de single kwam het eerst binnen, en het album opende op twee nummers.
      for (final volgorde in [true, false]) {
        final dz = [
          _dz('Taking Chances', RecordKind.single, 2, '2008-01-01'),
          _dz('Taking Chances', RecordKind.album, 1, '2007-11-12'),
        ];
        final uit = mergeDiscography([volgorde ? dz : dz.reversed.toList()]);
        expect(uit, hasLength(2));
        final album = uit.singleWhere((r) => r.kind == RecordKind.album);
        final single = uit.singleWhere((r) => r.kind == RecordKind.single);
        expect(album.refs[DiscoSource.deezer]!.intId, 1);
        expect(album.cover, 'https://dz/1.jpg');
        expect(single.refs[DiscoSource.deezer]!.intId, 2);
      }
    });

    test('Alabina: een cassette-album uit 1993 en de single uit 1996 blijven twee platen', () {
      final uit = mergeDiscography([
        [_dz('Alabina', RecordKind.single, 616311, '1996-01-01')],
        [_mb('Alabína', RecordKind.single, '1996-03-26')],
        [_dg('Alabina', RecordKind.album, 37060665, '1993')],
      ]);
      expect(uit, hasLength(2));
      final album = uit.singleWhere((r) => r.blok == RecordKind.album);
      expect(album.year, 1993);
      expect(album.refs.containsKey(DiscoSource.deezer), isFalse, reason: 'geen link naar de single');
      final single = uit.singleWhere((r) => r.blok == RecordKind.single);
      expect(single.sources, {DiscoSource.deezer, DiscoSource.musicbrainz});
      expect(single.year, 1996);
    });

    test('alleen Deezer zegt "single" over wat de anderen een album noemen: één plaat (Unbreakable, 19 nummers)', () {
      final uit = mergeDiscography([
        [_dz('Unbreakable', RecordKind.single, 913879911, '2015-10-02')],
        [_mb('Unbreakable', RecordKind.album, '2015-10-02')],
        [_dg('Unbreakable', RecordKind.album, 892999, '2015')],
      ]);
      expect(uit, hasLength(1));
      expect(uit.single.kind, RecordKind.album);
      expect(uit.single.refs[DiscoSource.deezer]!.intId, 913879911);
    });

    test('...maar niet als Deezer zelf ook een album met die titel heeft', () {
      final uit = mergeDiscography([
        [_dz('Funhouse', RecordKind.album, 227687, '2008-10-24'), _dz('Funhouse', RecordKind.single, 369725, '2009-07-20')],
        [_mb('Funhouse', RecordKind.album, '2008-10-24')],
      ]);
      expect(uit, hasLength(2));
      expect(uit.singleWhere((r) => r.kind == RecordKind.album).refs[DiscoSource.deezer]!.intId, 227687);
    });

    test('een regel zonder mening (Discogs-master zonder formaat) gaat bij de single, zoals altijd', () {
      // Met MusicBrainz er ook bij als single: dan geldt de uitzondering voor Deezer niet, en moet deze
      // regel het alleen doen.
      final uit = mergeDiscography([
        [_dz('Comme toi', RecordKind.single, 6663781, '2013-06-04')],
        [_mb('Comme toi', RecordKind.single, '1999-11-30')],
        [_dg('Comme Toi', RecordKind.other, 1400008, '1999')],
      ]);
      expect(uit, hasLength(1));
      expect(uit.single.kind, RecordKind.single);
      expect(uit.single.sources, {DiscoSource.deezer, DiscoSource.musicbrainz, DiscoSource.discogs});
    });

    test('een EP en een single met dezelfde titel blijven één plaat (allebei klein werk)', () {
      final uit = mergeDiscography([
        [_dz('True Blue', RecordKind.ep, 647709561, '1986-09-17')],
        [_mb('True Blue', RecordKind.single, '1986-09-17')],
      ]);
      expect(uit, hasLength(1));
    });

    test('een single met een aanduiding vouwt niet in het album ("… (Bande originale du film)")', () {
      final uit = mergeDiscography([
        [_mb('Madame Claude', RecordKind.album, '1977')],
        [_dz('Madame Claude (Bande originale du film)', RecordKind.single, 9, '2021-01-01')],
      ]);
      expect(uit, hasLength(2));
    });
  });

  test('zoekAlbum kiest het album als ook de single met die naam er staat', () async {
    final c = _NepCatalogus([
      const CatalogAlbum(369725, 'Funhouse', null, '2009-07-20', 3, 'single'),
      const CatalogAlbum(227687, 'Funhouse', null, '2008-10-24', 13, 'album'),
    ]);
    final hit = await c.zoekAlbum('P!nk', 'Funhouse');
    expect(hit?.album.id, 227687);
  });

  group('Deezer ontdubbelt per titel én maat', () {
    CatalogAlbum a(int id, String titel, String soort, String datum) => CatalogAlbum(id, titel, null, datum, 0, soort);

    test('DE KERN: de nieuwere single "Funhouse" duwt het album niet weg', () {
      final uit = CatalogService.ontdubbelArtiestAlbums([
        a(227687, 'Funhouse', 'album', '2008-10-24'),
        a(369725, 'Funhouse', 'single', '2009-07-20'),
      ]);
      expect(uit.map((x) => x.id), [369725, 227687], reason: 'allebei, nieuwste eerst');
    });

    test('heruitgaven van hetzelfde album: de nieuwste blijft', () {
      final uit = CatalogService.ontdubbelArtiestAlbums([
        a(227687, 'Funhouse', 'album', '2008-10-24'),
        a(7058960, 'Funhouse', 'album', '2010-01-01'),
        a(1, 'Funhouse', 'ep', '2009-01-01'),
        a(2, 'funhouse', 'single', '2009-07-20'),
      ]);
      expect(uit.map((x) => x.id).toSet(), {7058960, 2}, reason: 'één album en één klein werk');
    });
  });
}

/// Deezer zonder netwerk: één artiest, en de lijst die artistAlbums zou geven (nieuwste eerst).
class _NepCatalogus extends CatalogService {
  _NepCatalogus(this.albums);
  final List<CatalogAlbum> albums;

  @override
  Future<List<CatalogArtist>> searchArtists(String q) async => [CatalogArtist(1, q, null, albums.length)];

  @override
  Future<List<CatalogAlbum>> artistAlbums(int artistId) async => albums;
}
