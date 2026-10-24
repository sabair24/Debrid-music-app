// Seal heeft twee albums die "Seal" heten (1991 en 1994), en MusicBrainz kent er nog een derde: een krantenuitgave uit
// 2007 (The Mail on Sunday). Saber, 24-10-2026: "geen resultaat voor dit album seal 1991 ???" — "Geen tracklijst
// gevonden", met de hoes van de krant — en "hij maakt geen onderscheidt tussen album seal 1991 en 1994". Op titel
// samengevoegd werden de drie één regel. Gemeten bij MusicBrainz en Deezer op 24-10-2026 (de nummers hieronder).
import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/discography.dart';
import 'package:flutter_test/flutter_test.dart';

DiscoRelease _dz(int id, String datum, String hoes, {String titel = 'Seal'}) => DiscoRelease(
      title: titel,
      kind: RecordKind.album,
      firstDate: datum,
      cover: hoes,
      trackCount: 11,
      sources: const {DiscoSource.deezer},
      refs: {DiscoSource.deezer: CatalogRef.deezer(id)},
    );

DiscoRelease _mb(String id, String datum, {RecordKind kind = RecordKind.album, String titel = 'Seal'}) => DiscoRelease(
      title: titel,
      kind: kind,
      firstDate: datum,
      sources: const {DiscoSource.musicbrainz},
      refs: {DiscoSource.musicbrainz: CatalogRef.musicbrainzGroup(id)},
    );

const _mb1991 = '97375917-d328-3738-a556-9edfb489cdad';
const _mb1994 = '3bb226b7-db0b-3288-bea4-e2fecbe20c20';
const _mb2007 = '5465b2ec-2b45-4c34-aefb-6258be6843f0';

void main() {
  final deezer = [_dz(86422, '1991-06-11', 'dz-1991.jpg'), _dz(467277, '1994-05-31', 'dz-1994.jpg')];
  final mb = [
    _mb(_mb1991, '1991-05-20'),
    _mb(_mb1994, '1994-05-23'),
    _mb(_mb2007, '2007-10-28', kind: RecordKind.compilation),
    // Genoeg albums voor "MusicBrainz beslist" (kMbGenoeg).
    _mb('mb-iv', '2003-06-22', titel: 'Seal IV'),
    _mb('mb-system', '2007-11-12', titel: 'System'),
    _mb('mb-soul', '2008-11-10', titel: 'Soul'),
  ];

  String? mbVan(DiscoRelease r) => r.refs[DiscoSource.musicbrainz]?.id;
  String? dzVan(DiscoRelease r) => r.refs[DiscoSource.deezer]?.id;

  test('drie platen "Seal": elk een eigen regel met zijn eigen Deezer-album en hoes', () {
    final samen = mergeDiscography([deezer, mb, const []]);
    final seal = samen.where((r) => r.key == 'seal').toList();
    expect(seal, hasLength(3));
    final eerste = seal.firstWhere((r) => mbVan(r) == _mb1991);
    final tweede = seal.firstWhere((r) => mbVan(r) == _mb1994);
    final krant = seal.firstWhere((r) => mbVan(r) == _mb2007);
    expect(dzVan(eerste), '86422');
    expect(eerste.cover, 'dz-1991.jpg');
    expect(dzVan(tweede), '467277');
    expect(tweede.cover, 'dz-1994.jpg');
    expect(dzVan(krant), isNull);
    expect(krant.cover, isNull, reason: 'geen hoes van een ander album');
  });

  test('ook in de andere volgorde (MusicBrainz eerst), en door volgensMusicBrainz heen', () {
    final samen = mergeDiscography([mb, deezer, const []]);
    final rijen = volgensMusicBrainz(samen, mb, artiest: 'Seal').where((r) => r.key == 'seal').toList();
    expect(rijen, hasLength(3));
    expect({for (final r in rijen) mbVan(r): dzVan(r)}, {_mb1991: '86422', _mb1994: '467277', _mb2007: null});
    expect(rijen.firstWhere((r) => mbVan(r) == _mb2007).kind, RecordKind.compilation);
  });

  test('een losse Deezer-regel koppelt aan de MusicBrainz-plaat van het dichtstbijzijnde jaar', () {
    // Zonder dat Deezer en MusicBrainz al samen staan: volgensMusicBrainz koppelt ze zelf.
    final rijen = volgensMusicBrainz([...deezer], mb, artiest: 'Seal').where((r) => r.key == 'seal').toList();
    expect({for (final r in rijen) mbVan(r): dzVan(r)}, {_mb1991: '86422', _mb1994: '467277', _mb2007: null});
  });

  test('een heruitgave bij een ándere bron blijft samengaan; dezelfde plaat binnen een jaar ook', () {
    final r = mergeDiscography([
      [_dz(1, '2003-10-07', 'remaster.jpg', titel: 'Back in Black')],
      [_mb('mb-bib', '1980-07-25', titel: 'Back in Black')],
    ]);
    expect(r, hasLength(1), reason: 'Deezer kent hem maar onder één nummer');
    final s = mergeDiscography([
      [_dz(1, '1991-06-11', 'a.jpg'), _dz(2, '1991-05-24', 'b.jpg')],
    ]);
    expect(s, hasLength(1), reason: 'minder dan twee jaar uit elkaar: dezelfde plaat');
  });

  test('hoezen per plaat: een hoes onder de titel gaat niet naar een titel die drie platen dragen', () {
    final rijen = [_mb(_mb1991, '1991-05-20'), _mb(_mb1994, '1994-05-23'), _mb(_mb2007, '2007-10-28')];
    final opTitel = vulHoezenAan(rijen, {'seal': 'mail.jpg'});
    expect(opTitel.every((r) => r.cover == null), isTrue);
    final perGroep = vulHoezenAan(rijen, {'mb:$_mb2007': 'mail.jpg', 'mb:$_mb1994': 'seal2.jpg'});
    expect({for (final r in perGroep) mbVan(r): r.cover}, {_mb1991: null, _mb1994: 'seal2.jpg', _mb2007: 'mail.jpg'});
    expect([for (final g in groepenZonderHoes(rijen)) g.sleutel], ['mb:$_mb1991', 'mb:$_mb1994', 'mb:$_mb2007']);
    // Een titel die maar één plaat draagt, krijgt de hoes onder zijn titel zoals vroeger.
    expect(vulHoezenAan([_mb('mb-iv', '2003-06-22', titel: 'Seal IV')], {'seal iv': 'iv.jpg'}).single.cover, 'iv.jpg');
  });
}
