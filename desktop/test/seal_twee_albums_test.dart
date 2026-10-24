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

DiscoRelease _dg(CatalogRef ref, String jaar, RecordKind kind, String hoes, {String titel = 'Seal'}) => DiscoRelease(
      title: titel,
      kind: kind,
      firstDate: jaar,
      cover: hoes,
      sources: const {DiscoSource.discogs},
      refs: {DiscoSource.discogs: ref},
    );

// Discogs, in de volgorde waarin vanDiscogs ze gaf (gemeten 24-10-2026). De dvd, de krant en de 2004-regels droegen
// allemaal de hoes van de krant (Discogs-uitgave 1511987, "The Mail On Sunday"), via de zoeksweep op titel.
final _discogs = [
  _dg(CatalogRef.discogsRelease(26081905), '2008', RecordKind.video, 'krant.jpg'),
  _dg(CatalogRef.discogsRelease(38613441), '2007', RecordKind.compilation, 'krant.jpg'),
  _dg(CatalogRef.discogsMaster(386611), '2007', RecordKind.compilation, 'krant.jpg'),
  _dg(CatalogRef.discogsRelease(14596580), '2004', RecordKind.other, 'krant.jpg'),
  _dg(CatalogRef.discogsMaster(1284411), '2004', RecordKind.other, 'ander-2004.jpg'),
  _dg(CatalogRef.discogsMaster(61206), '1994', RecordKind.album, 'dg-1994.jpg'),
  _dg(CatalogRef.discogsMaster(363645), '1991', RecordKind.video, 'vhs-1991.jpg'),
  _dg(CatalogRef.discogsMaster(61188), '1991', RecordKind.album, 'dg-1991.jpg'),
];

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
  test('Discogs in zijn eigen volgorde: de cd van 1991 en die van 1994 sluiten aan, niet de krant of de dvd', () {
    final samen = mergeDiscography([deezer, mb, _discogs]);
    final rijen = volgensMusicBrainz(samen, mb, artiest: 'Seal').where((r) => r.key == 'seal').toList();
    final eerste = rijen.firstWhere((r) => mbVan(r) == _mb1991);
    final tweede = rijen.firstWhere((r) => mbVan(r) == _mb1994);
    expect(eerste.refs[DiscoSource.discogs]?.id, '61188');
    expect(tweede.refs[DiscoSource.discogs]?.id, '61206');
    expect(eerste.cover, 'dz-1991.jpg');
    expect(tweede.cover, 'dz-1994.jpg');
    expect(eerste.kind, RecordKind.album);
  });

  test('zonder Deezer-album voor 1991: de hoes van de Discogs-cd, niet die van de krant', () {
    // Zoals vóór 24-10-2026: Deezer gaf per titel alleen de nieuwste ("Seal" 1994).
    final samen = mergeDiscography([[deezer.last], mb, _discogs]);
    final rijen = volgensMusicBrainz(samen, mb, artiest: 'Seal').where((r) => r.key == 'seal').toList();
    final eerste = rijen.firstWhere((r) => mbVan(r) == _mb1991);
    expect(eerste.cover, 'dg-1991.jpg');
    expect(eerste.refs[DiscoSource.discogs]?.id, '61188');
  });

  test('zonder MusicBrainz: een heruitgave die alleen Deezer kent valt weg, twee echte platen blijven', () {
    final toto = [
      _dz(1441741, '2006-04-14', 'toto-2006.jpg', titel: 'Toto'),
      _dz(116633, '1978-10-10', 'toto-1978.jpg', titel: 'Toto'),
    ];
    final metDiscogs = volgensMusicBrainz(
        mergeDiscography([toto, const [], [_dg(CatalogRef.discogsMaster(1), '1978', RecordKind.album, 'dg.jpg', titel: 'Toto')]]),
        const []);
    expect(metDiscogs.map((r) => r.refs[DiscoSource.deezer]?.id), ['116633']);
    final alleenDeezer = volgensMusicBrainz(mergeDiscography([toto]), const []);
    expect(alleenDeezer.map((r) => r.refs[DiscoSource.deezer]?.id), ['1441741'], reason: 'de nieuwste, zoals vroeger');
    final seal = volgensMusicBrainz(mergeDiscography([deezer, const [], _discogs]), const []);
    expect(seal.where((r) => r.key == 'seal' && r.refs.containsKey(DiscoSource.deezer)).map((r) => r.refs[DiscoSource.deezer]!.id).toSet(),
        {'86422', '467277'});
  });
  test('een titel met meer albums: een losse Deezer-heruitgave gaat niet naar de single (Eurythmics)', () {
    const t = 'Sweet Dreams (Are Made of This)';
    final dz = [
      _dz(1453419, '2018-04-13', '2018.jpg', titel: t),
      _dz(73280, '2003-10-21', '2003.jpg', titel: t),
      _dz(1453421, '1999-12-30', '1999.jpg', titel: t),
      _dz(121458, '1987-10-09', '1987.jpg', titel: t),
    ];
    final mbE = [
      _mb('mb-sd', '1983', titel: t),
      _mb('mb-sd-single', '1982', kind: RecordKind.single, titel: t),
      _mb('mb-garden', '1981-10-16', titel: 'In the Garden'),
      _mb('mb-touch', '1983-11-14', titel: 'Touch'),
    ];
    final rijen = volgensMusicBrainz(mergeDiscography([dz, mbE, const []]), mbE, artiest: 'Eurythmics');
    final single = rijen.firstWhere((r) => mbVan(r) == 'mb-sd-single');
    expect(dzVan(single), isNull, reason: 'een Deezer-album hoort niet bij een single');
    expect(dzVan(rijen.firstWhere((r) => mbVan(r) == 'mb-sd')), '121458', reason: 'het jaar dat het dichtst bij 1983 ligt');
  });
  test('kent MusicBrainz alleen de single, dan krijgt die het Deezer-album zoals vroeger (Johnny Hallyday)', () {
    const t = 'Rivière... Ouvre ton lit';
    final dz = [_dz(150699042, '2020-05-29', '2020.jpg', titel: t), _dz(242145, '2000-04-22', '2000.jpg', titel: t)];
    final mbJ = [
      _mb('mb-riv', '1969-03-10', kind: RecordKind.single, titel: t),
      _mb('mb-a', '1961', titel: 'Salut les copains'),
      _mb('mb-b', '1962', titel: 'Sings America'),
      _mb('mb-c', '1964', titel: 'Les Rocks les plus terribles'),
    ];
    final rijen = volgensMusicBrainz(mergeDiscography([dz, mbJ, const []]), mbJ, artiest: 'Johnny Hallyday');
    final single = rijen.firstWhere((r) => mbVan(r) == 'mb-riv');
    expect(dzVan(single), isNotNull);
    expect(single.cover, isNotNull);
  });
}
