// MusicBrainz als enige pad voor de discografie (Saber, 20-10-2026: "gebruik dan 1 pad, MusicBrainz, wat
// het beste en precies is"). De titels zijn echt, uit de metingen van 20-10-2026 (remix_bij_albums_live_test).
import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/discography.dart';
import 'package:debridmusic/discography_service.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:flutter_test/flutter_test.dart';

var _mbNr = 0;
DiscoRelease _mb(String t, String? d, {RecordKind k = RecordKind.album}) => DiscoRelease(
      title: t,
      kind: k,
      firstDate: d,
      sources: const {DiscoSource.musicbrainz},
      refs: {DiscoSource.musicbrainz: CatalogRef.musicbrainzGroup('mb-${++_mbNr}')},
    );

DiscoRelease _dz(String t, String d, int id, {RecordKind k = RecordKind.album, String? hoes}) => DiscoRelease(
      title: t,
      kind: k,
      firstDate: d,
      cover: hoes,
      sources: const {DiscoSource.deezer},
      refs: {DiscoSource.deezer: CatalogRef.deezer(id)},
    );

DiscoRelease _dg(String t, String d) => DiscoRelease(
      title: t,
      kind: RecordKind.album,
      firstDate: d,
      sources: const {DiscoSource.discogs},
      refs: {DiscoSource.discogs: CatalogRef.discogsMaster(d.hashCode)},
    );

final _nu = DateTime(2026, 10, 20);

List<DiscoRelease> _pad(List<DiscoRelease> dz, List<DiscoRelease> mb, {List<DiscoRelease> dg = const [], String artiest = ''}) =>
    volgensMusicBrainz(mergeDiscography([dz, mb, dg]), mb, artiest: artiest, nu: _nu);

List<String> _blok(List<DiscoRelease> l, RecordKind b) => [
      for (final r in vouwHeruitgaves(l))
        if (r.blok == b) r.title
    ];

void main() {
  group('MusicBrainz beslist', () {
    test('DE KERN: Alabina — alleen haar studioalbums; "L\'Essentiel" is een verzamelaar en blijft speelbaar', () {
      final mb = [
        _mb('Alabina: The Album', '1996'),
        _mb('The Album II', '1998'),
        _mb('Sahara', '1998'),
        _mb("L'Essentiel", '1999', k: RecordKind.compilation),
      ];
      final dz = [
        _dz("Alabina, l'essentiel", '1999-01-01', 9729628),
        _dz('The Album of Alabina & Los Niños de Sara', '2007-01-01', 41833),
        _dz('Gypsy Lounge', '2010-01-01', 506027),
        _dz('Alabina the Diva', '2014-01-01', 148240532),
      ];
      final uit = _pad(dz, mb, artiest: 'Alabina');
      expect(_blok(uit, RecordKind.album), ['Alabina: The Album', 'The Album II', 'Sahara']);
      expect(_blok(uit, RecordKind.compilation), ["L'Essentiel"]);
      expect(uit.firstWhere((r) => r.title == "L'Essentiel").refs[DiscoSource.deezer]?.intId, 9729628,
          reason: 'de Deezer-regel met de artiestnaam ervoor is dezelfde plaat: zo is hij af te spelen');
      expect(uit.where((r) => r.title.contains('Alabina, l')), isEmpty, reason: 'en staat niet nog eens apart');
    });

    test('de soort van MusicBrainz wint van Deezers "album"', () {
      final mb = [
        _mb('Unison', '1990'),
        _mb('Falling Into You', '1996'),
        _mb("Let's Talk About Love", '1997'),
        _mb('Gold', '2006', k: RecordKind.compilation),
        _mb('A New Day… Live in Las Vegas', '2004', k: RecordKind.live),
      ];
      final uit = _pad([_dz('Gold', '2006-01-01', 1210684)], mb);
      expect(_blok(uit, RecordKind.album), ['Unison', 'Falling Into You', "Let's Talk About Love"]);
      expect(_blok(uit, RecordKind.compilation), ['Gold']);
      expect(uit.firstWhere((r) => r.title == 'Gold').refs[DiscoSource.deezer]?.intId, 1210684);
    });

    test('ook andersom: Deezer zegt "verzamelaar", MusicBrainz "album" — dan album', () {
      final mb = [_mb('Cheap Seats', '1993'), _mb('Roll On', '1984'), _mb('The Touch', '1986')];
      final uit = _pad([_dz('Cheap Seats', '1993-02-23', 114146, k: RecordKind.compilation)], mb);
      expect(_blok(uit, RecordKind.album), ['Cheap Seats', 'Roll On', 'The Touch']);
    });

    test('Deezers verzamelaars en Discogs\' concertdownloads die MusicBrainz niet kent, vallen weg', () {
      final mb = [_mb('Gang', '1986'), _mb('Cadillac', '1989'), _mb('Lorada', '1995')];
      final uit = _pad(
        [
          _dz('Anthologie 1960/1963', '1998-01-01', 217894),
          _dz('Les Indispensables', '2002-01-01', 72306),
          _dz('Sang Pour Sang / Lorada', '2002-01-01', 1252896),
        ],
        mb,
        dg: [_dg('Paris, France May 19, 2023', '2023')],
      );
      expect(uit.map((r) => r.title), ['Gang', 'Cadillac', 'Lorada']);
    });

    test('elke releasegroep precies één keer, met de titel en de datum van MusicBrainz', () {
      final mb = [_mb('Erotica', '1992-10-20'), _mb('Bedtime Stories', '1994'), _mb('Ray of Light', '1998')];
      final uit = _pad([_dz('Erotica', '2005-01-01', 1), _dz('Bedtime Stories', '1994-10-25', 2)], mb);
      expect(uit, hasLength(3));
      expect(uit.firstWhere((r) => r.title == 'Erotica').firstDate, '1992-10-20',
          reason: 'het jaar van de plaat, niet van Deezers heruitgave');
      expect(uit.firstWhere((r) => r.title == 'Erotica').refs[DiscoSource.deezer]?.intId, 1);
      final vroeg = _pad([_dz('Ray of Light', '1997-01-01', 3)], mb);
      expect(vroeg.firstWhere((r) => r.title == 'Ray of Light').firstDate, '1998',
          reason: 'ook als een andere bron een vroegere datum noemt');
    });

    test('een Deezer-editie van een MusicBrainz-album blijft, onder de uitgaven', () {
      final mb = [_mb('Rebel Heart', '2015'), _mb('MDNA', '2012'), _mb('Madame X', '2019')];
      final uit = _pad([_dz('Rebel Heart (Deluxe)', '2015-03-06', 3), _dz('Erotica (PA Version)', '1992-01-01', 4)], mb);
      expect(_blok(uit, RecordKind.albumVersie), ['Rebel Heart (Deluxe)'],
          reason: 'nummers die alleen op de deluxe staan; "Erotica" kent deze MusicBrainz-lijst niet');
      expect(_blok(uit, RecordKind.album), ['Rebel Heart', 'MDNA', 'Madame X']);
    });

    test('een nieuwe plaat die MusicBrainz nog niet heeft, blijft — een nieuwe heruitgave niet', () {
      final mb = [_mb('Insolitudes', '1973'), _mb('Vie', '1970'), _mb('Gang', '1986')];
      final uit = _pad(
        [
          _dz('Zo Kan Het Dus Ook', '2026-09-12', 5),
          _dz('Insolitudes (Johnny 73)', '2026-05-01', 6),
          _dz('Oude Deezer-plaat', '2026-04-01', 7),
        ],
        mb,
      );
      expect(uit.map((r) => r.title), containsAll(['Zo Kan Het Dus Ook']));
      expect(uit.map((r) => r.title), isNot(contains('Insolitudes (Johnny 73)')),
          reason: 'een versie van iets wat MusicBrainz al heeft');
      expect(uit.map((r) => r.title), isNot(contains('Oude Deezer-plaat')), reason: 'ouder dan zes maanden');
    });

    test('een nieuwe Deezer-regel met de artiestnaam die aan MusicBrainz gekoppeld is, staat er één keer', () {
      final mb = [_mb('Zo Kan Het Dus Ook', '2026-09-12'), _mb('Vuur en vlam', '2025'), _mb('Ver weg', '2021')];
      final uit = _pad([_dz('Niels Destadsbader - Zo Kan Het Dus Ook', '2026-09-12', 11)], mb,
          artiest: 'Niels Destadsbader');
      expect(uit.map((r) => r.title), ['Zo Kan Het Dus Ook', 'Vuur en vlam', 'Ver weg']);
      expect(uit.first.refs[DiscoSource.deezer]?.intId, 11);
    });

    test('DE GRENS: kent MusicBrainz minder dan drie albums, dan blijft de lijst zoals hij was', () {
      final mb = [_mb('Eerste', '2020'), _mb('Tweede', '2022')];
      final samen = mergeDiscography([
        [_dz('Derde', '2024-01-01', 8)],
        mb,
      ]);
      expect(volgensMusicBrainz(samen, mb, nu: _nu), same(samen));
      expect(volgensMusicBrainz(samen, const [], nu: _nu), same(samen), reason: 'MusicBrainz onbereikbaar');
    });

    test('DE GRENS: de artiestnaam koppelt nooit een single aan een album', () {
      final mb = [_mb('Christmas', '1985'), _mb('Roll On', '1984'), _mb('The Touch', '1986')];
      final uit = _pad([_dz('Alabama Christmas', '1988-01-01', 9, k: RecordKind.single)], mb, artiest: 'Alabama');
      expect(uit.firstWhere((r) => r.title == 'Christmas').refs[DiscoSource.deezer], isNull);
    });

    test('ook met de naam aan de MusicBrainz-kant: "Céline Dion chante Noël" krijgt Deezers "Chante Noël"', () {
      final mb = [_mb('Céline Dion chante Noël', '1981'), _mb('Unison', '1990'), _mb('D\'eux', '1995')];
      final uit = _pad([_dz('Chante Noël', '1981-01-01', 10)], mb, artiest: 'Céline Dion');
      expect(uit, hasLength(3));
      expect(uit.firstWhere((r) => r.title == 'Céline Dion chante Noël').refs[DiscoSource.deezer]?.intId, 10);
    });
  });

  // Saber, 28-10-2026: "waarom staat de album millenium 2.0 niet in het overzicht, staat wel bij tidal". Gemeten:
  // MusicBrainz zet "Millennium 2.0" (deluxe edition, 25th anniversary edition) in de groep van Millennium
  // (a8fb6ac6), Deezer heeft hem als album 782757601 van 11-07-2025. "2.0" is geen staart en hij is ouder dan een
  // halfjaar, dus viel hij weg. Saber koos: onder Uitgaven, MusicBrainz beslist.
  group('een uitgave die MusicBrainz binnen een album kent', () {
    const millennium = 'a8fb6ac6-a659-320f-8736-87b52ad65e3a';
    DiscoRelease mbGroep(String t, String d, String id, {RecordKind k = RecordKind.album}) => DiscoRelease(
          title: t,
          kind: k,
          firstDate: d,
          sources: const {DiscoSource.musicbrainz},
          refs: {DiscoSource.musicbrainz: CatalogRef.musicbrainzGroup(id)},
        );
    final mb = [
      mbGroep('Backstreet Boys', '1996-05-06', 'g-bsb'),
      mbGroep("Backstreet's Back", '1997-08-11', 'g-back'),
      mbGroep('Millennium', '1999-04-28', millennium),
      mbGroep('Black & Blue', '2000-11-21', 'g-bb'),
      mbGroep('The Hits: Chapter One', '2001-10-23', 'g-hits', k: RecordKind.compilation),
    ];
    final dz = [
      _dz('Millennium', '1999-05-18', 1205922),
      _dz('Millennium 2.0', '2025-07-11', 782757601),
    ];
    List<DiscoRelease> pad({Map<String, String> groepVan = const {}}) => volgensMusicBrainz(
        mergeDiscography([dz, mb]), mb,
        artiest: 'Backstreet Boys', nu: _nu, mbGroepVan: groepVan);

    test('DE KERN: Millennium 2.0 komt onder Uitgaven, en Millennium blijft één album', () {
      final uit = pad(groepVan: {'782757601': millennium});
      expect(_blok(uit, RecordKind.albumVersie), ['Millennium 2.0']);
      expect(_blok(uit, RecordKind.album).where((t) => t.startsWith('Millennium')), ['Millennium']);
      expect(uit.firstWhere((r) => r.title == 'Millennium 2.0').refs[DiscoSource.deezer]?.intId, 782757601,
          reason: 'af te spelen via Deezer');
    });

    test('zonder antwoord van MusicBrainz blijft hij weg, zoals voorheen', () {
      expect(pad().where((r) => r.title == 'Millennium 2.0'), isEmpty);
    });

    test('DE GRENS: alleen onder een ALBUM van MusicBrainz, niet onder een verzamelaar of een onbekende groep', () {
      expect(pad(groepVan: {'782757601': 'g-hits'}).where((r) => r.title == 'Millennium 2.0'), isEmpty);
      expect(pad(groepVan: {'782757601': 'g-niet-van-deze-artiest'}).where((r) => r.title == 'Millennium 2.0'),
          isEmpty);
    });

    test('wegGevallenAlbums noemt alleen wat wegviel, niet wat aan een MusicBrainz-plaat hangt', () {
      final samen = mergeDiscography([dz, mb]);
      final weg = wegGevallenAlbums(samen, volgensMusicBrainz(samen, mb, artiest: 'Backstreet Boys', nu: _nu));
      expect([for (final r in weg) r.title], ['Millennium 2.0'],
          reason: 'Deezers Millennium zit al in de MusicBrainz-regel; daar hoeft niets gevraagd');
    });

    MbRelease zoek(String titel, String artiest, String? groep) => MbRelease.from({
          'id': 'r-$titel',
          'title': titel,
          'artist-credit': [
            {'name': artiest}
          ],
          if (groep != null) 'release-group': {'id': groep},
        });

    test('de zoekuitslag: precies die titel van precies die artiest', () {
      final uitslag = [
        zoek('Millennium', 'Backstreet Boys', millennium),
        zoek('Millennium 2.0', 'Backstreet Boys Tribute Band', 'g-tribute'),
        zoek('Millennium 2.0', 'Backstreet Boys', millennium),
      ];
      expect(groepUitZoekuitslag('Backstreet Boys', 'Millennium 2.0', uitslag), millennium);
      expect(groepUitZoekuitslag('Backstreet Boys', 'Millennium 2.0', uitslag.take(2).toList()), isNull,
          reason: 'Millennium zelf en een naamgenoot zeggen niets over waar 2.0 hoort');
      expect(groepUitZoekuitslag('Backstreet Boys', 'Millennium 2.0', [zoek('Millennium 2.0', 'Backstreet Boys', null)]),
          isNull);
    });
  });
}
