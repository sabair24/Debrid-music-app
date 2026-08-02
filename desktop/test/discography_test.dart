/// Wat een discografie uit drie catalogi tot één lijst maakt.
///
/// De dure fout die hier vastgehouden wordt is niet "er ontbreekt een plaat" maar het omgekeerde:
/// twee bronnen die dezelfde plaat net anders spellen leveren twee regels op die allebei als "heb ik"
/// worden afgevinkt. Dat gebeurt vandaag al — `catalog.dart` dedupliceert op `toLowerCase()` terwijl
/// de bezitscontrole `normKey` gebruikt — en met drie bronnen wordt het drie regels.
///
/// De belangrijkste test van dit bestand is die op de VOLGORDE-ONAFHANKELIJKHEID. De pagina toont
/// Deezer meteen en vult MusicBrainz en Discogs erachteraan in; als samenvoegen niet commutatief is,
/// verandert de lijst onder je handen terwijl je kijkt.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/discography.dart';

DiscoRelease _dz(String titel, {String? datum, String? cover, int tracks = 0, int id = 1}) =>
    DiscoRelease(
      title: titel,
      kind: RecordKind.album,
      firstDate: datum,
      cover: cover,
      trackCount: tracks,
      sources: const {DiscoSource.deezer},
      refs: {DiscoSource.deezer: CatalogRef.deezer(id)},
    );

DiscoRelease _mb(String titel, {String? datum, RecordKind kind = RecordKind.album}) => DiscoRelease(
      title: titel,
      kind: kind,
      firstDate: datum,
      sources: const {DiscoSource.musicbrainz},
      refs: {DiscoSource.musicbrainz: CatalogRef.musicbrainzGroup('mbid-$titel')},
    );

DiscoRelease _dg(String titel, {String? datum, String? cover, int id = 7}) => DiscoRelease(
      title: titel,
      kind: RecordKind.album,
      firstDate: datum,
      cover: cover,
      sources: const {DiscoSource.discogs},
      refs: {DiscoSource.discogs: CatalogRef.discogsMaster(id)},
    );

void main() {
  group('een verzamelaar mag niet tot album gedegradeerd worden', () {
    // Zolang Discogs-masters `other` droegen verloren ze altijd, en viel dit niet op. Nu ze hun
    // formaat uit de zoeksweep krijgen doen ze mee in de soortkeuze — en die koos de LAAGSTE
    // leesrang, waar album (0) boven compilation (4) staat. Dat is precies de fout die kindFromMb
    // bestaat om te voorkomen, één laag hoger teruggekomen.
    test('MusicBrainz zegt verzamelaar, Discogs zegt alleen "Album"', () {
      final mb = DiscoRelease(
        title: 'The Collection',
        kind: RecordKind.compilation,
        sources: const {DiscoSource.musicbrainz},
        refs: {DiscoSource.musicbrainz: CatalogRef.musicbrainzGroup('x')},
      );
      final dg = DiscoRelease(
        title: 'The Collection',
        kind: kindFromDiscogs('CD, Album'),
        sources: const {DiscoSource.discogs},
        refs: {DiscoSource.discogs: CatalogRef.discogsMaster(9)},
      );
      expect(dg.kind, RecordKind.album, reason: 'zo leest Discogs het formaat nu eenmaal');
      // "Compilation" in de tweede lijst van MusicBrainz is een UITSPRAAK dat het een verzamelaar is;
      // "Album" in een Discogs-formaat is dat niet — dat staat op elke lp. De uitspraak wint.
      expect(mb.mergedWith(dg).kind, RecordKind.compilation);
      expect(dg.mergedWith(mb).kind, RecordKind.compilation, reason: 'en in beide volgordes');
      expect(mb.mergedWith(dg).blok, RecordKind.compilation);
    });

    test('Deezer zegt verzamelaar, een andere bron zegt album', () {
      final dz = DiscoRelease(
        title: 'Greatest Hits',
        kind: kindFromDeezer('compile'),
        sources: const {DiscoSource.deezer},
        refs: {DiscoSource.deezer: CatalogRef.deezer(3)},
      );
      final mb = _mb('Greatest Hits');
      expect(dz.mergedWith(mb).kind, RecordKind.compilation);
      expect(mb.mergedWith(dz).kind, RecordKind.compilation);
    });

    test('zonder verzamelaar in het spel blijft de oude regel gelden', () {
      // Eén bron die "overig" zegt mag een album niet degraderen — dat was de bestaande afspraak en
      // die moet blijven staan.
      final a = _dz('Thriller');
      final o = DiscoRelease(
        title: 'Thriller',
        kind: RecordKind.other,
        sources: const {DiscoSource.discogs},
        refs: {DiscoSource.discogs: CatalogRef.discogsMaster(1)},
      );
      expect(a.mergedWith(o).kind, RecordKind.album);
      expect(o.mergedWith(a).kind, RecordKind.album);
      // En een single naast een album blijft de bestaande keuze volgen.
      expect(_dz('X').mergedWith(_mb('X', kind: RecordKind.single)).kind, RecordKind.album);
    });

    test('een master zonder formaat blijft eerlijk "overig"', () {
      // De regressiebewaker op de aanleiding: `/artists/{id}/releases` geeft een master geen
      // format-veld, en een lege string mag nooit stilletjes iets anders gaan betekenen.
      expect(kindFromDiscogs(''), RecordKind.other);
      expect(kindFromDiscogs('Vinyl, LP, Album, Compilation'), RecordKind.compilation);
    });
  });

  group('hoezen aanvullen zonder rijen te verzinnen', () {
    // Saber wees het aan bij Céline Dion: een blok Verzamelaars vol grijze schijven. GEMETEN: 54 van
    // haar 55 hoesloze regels kent alléén MusicBrainz, dat op releasegroep-niveau nooit een hoes
    // levert — en de Cover Art Archive daar evenmin (0 van 25 getoetst).
    test('een regel zonder hoes krijgt die van de sweep', () {
      final uit = vulHoezenAan([_mb('The French Collection II')], {
        discoKey('The French Collection II'): 'http://img/fc2.jpg',
      });
      expect(uit.single.cover, 'http://img/fc2.jpg');
    });

    test('een hoes die er al is blijft staan', () {
      // Aanvullen, niet vervangen. Anders kan deze stap een goede hoes door een mindere ruilen, en
      // dat is precies het soort fout dat je nooit meer opmerkt.
      final uit = vulHoezenAan([_dz('Unison', cover: 'http://echt/unison.jpg')], {
        discoKey('Unison'): 'http://sweep/anders.jpg',
      });
      expect(uit.single.cover, 'http://echt/unison.jpg');
    });

    test('wat de sweep niet kent blijft zonder hoes, en de regel blijft bestaan', () {
      final uit = vulHoezenAan([_mb('Mon Ami')], {discoKey('Iets anders'): 'http://img/x.jpg'});
      expect(uit, hasLength(1));
      expect(uit.single.cover, isNull);
    });

    test('aanvullen voegt nooit een regel toe, ook niet als de tabel er tien kent', () {
      final uit = vulHoezenAan([_mb('Mon Ami')], {
        discoKey('Mon Ami'): 'a',
        discoKey('Een plaat die niet in de lijst staat'): 'b',
        discoKey('En nog een'): 'c',
      });
      expect(uit, hasLength(1));
    });

    test('twee keer aanvullen verandert niets meer', () {
      final tabel = {discoKey('Mon Ami'): 'http://img/ma.jpg'};
      final een = vulHoezenAan([_mb('Mon Ami')], tabel);
      final twee = vulHoezenAan(een, tabel);
      expect(twee.single.cover, een.single.cover);
      expect(twee, hasLength(1));
    });

    test('de rest van de regel blijft heel', () {
      // Een aangevulde regel wordt opnieuw gebouwd; alles behalve de hoes moet erdoorheen komen,
      // anders verliest hij zijn verwijzing en opent hij niets meer.
      final bron = _mb('Mon Ami', datum: '1997-01-01', kind: RecordKind.compilation);
      final uit = vulHoezenAan([bron], {discoKey('Mon Ami'): 'http://img/ma.jpg'}).single;
      expect(uit.title, bron.title);
      expect(uit.firstDate, '1997-01-01');
      expect(uit.kind, RecordKind.compilation);
      expect(uit.sources, bron.sources);
      expect(uit.openRef, isNotNull);
    });
  });

  group('welk soort uitgave is dit', () {
    test('elke bron spelt het anders', () {
      expect(kindFromDeezer('compile'), RecordKind.compilation);
      expect(kindFromDeezer('EP'), RecordKind.ep);
      expect(kindFromDeezer('rommel'), RecordKind.other);
      expect(kindFromDiscogs('LP, Album, Reissue'), RecordKind.album);
      expect(kindFromDiscogs('CD, Single'), RecordKind.single);
    });

    test('een verzamelaar staat bij MusicBrainz als Album met een tweede etiket', () {
      // Alleen naar primaryType kijken zet elke verzamelbox tussen de studioalbums — en dat is
      // precies wat een discografie onleesbaar maakt.
      expect(kindFromMb('Album', ['Compilation']), RecordKind.compilation);
      expect(kindFromMb('Album', []), RecordKind.album);
      expect(kindFromMb('Album', ['Live']), RecordKind.album,
          reason: 'een livealbum blijft een album; alleen compilatie verandert de indeling');
    });
  });

  group('wanneer zijn twee regels dezelfde plaat', () {
    test('de krulapostrof en de rechte zijn één plaat', () {
      // De val waar dit hele bestand om draait: op `toLowerCase()` zijn dit twee platen, op `normKey`
      // één. De bibliotheek gebruikt `normKey`, dus dat moet hier ook.
      expect(discoKey("Backstreet's Back"), discoKey('Backstreet’s Back'));
      expect(discoKey('Thriller'), discoKey('  thriller '));
      expect(discoKey('Beyoncé'), discoKey('Beyonce'));
    });

    test('een deluxe valt NIET samen met het gewone album', () {
      // Dit stond eerst andersom, en dat was fout. Een deluxe is geen andere PERSING maar een ander
      // product: er staan nummers op die op het gewone album niet staan. Wegstrijken liet die uitgave
      // stilzwijgend uit beeld verdwijnen -- en juist die wil je kunnen kiezen.
      expect(discoKey('30 (Deluxe Edition)'), isNot(discoKey('30')));
      expect(discoKey('Thriller (25th Anniversary Edition)'), isNot(discoKey('Thriller')));
    });

    test('maar hij komt wel in een eigen blok terecht', () {
      expect(heeftEditieStaart('30 (Deluxe Edition)'), isTrue);
      expect(heeftEditieStaart('30 (Deluxe Edition) [2021 Remaster]'), isTrue,
          reason: 'Discogs plakt er graag twee achter elkaar');
      expect(heeftEditieStaart('Thriller (25th Anniversary Edition)'), isTrue);
      // En de grens: dit zijn geen uitgave-staarten maar deel van de titel.
      expect(heeftEditieStaart('30 ans de succès'), isFalse);
      expect(heeftEditieStaart('Thriller (Live)'), isFalse);
      expect(heeftEditieStaart('Thriller'), isFalse);
    });
  });

  group('blokken', () {
    test('een deluxe staat onder "Andere uitgaves", niet tussen de albums', () {
      final blokken = inBlokken([
        _dz('30', datum: '2021-11-19'),
        _dz('30 (Deluxe Edition)', datum: '2021-11-19'),
        DiscoRelease(title: 'Easy On Me', kind: RecordKind.single, firstDate: '2021-10-15'),
        DiscoRelease(title: 'Verzamelaar', kind: RecordKind.compilation, firstDate: '2015-01-01'),
      ], DiscoSort.datum, {});

      expect(blokken.map((b) => b.soort).toList(),
          [RecordKind.album, RecordKind.albumVersie, RecordKind.single, RecordKind.compilation]);
      expect(blokken.first.rijen.single.title, '30');
      expect(blokken[1].rijen.single.title, '30 (Deluxe Edition)');
    });

    test('lege blokken vallen weg', () {
      final blokken = inBlokken([_dz('Alleen dit')], DiscoSort.datum, {});
      expect(blokken, hasLength(1));
      expect(blokken.first.soort, RecordKind.album);
    });

    test('elk blok heeft een kop', () {
      for (final k in RecordKind.values) {
        expect(blokTitel(k), isNotEmpty);
      }
    });
  });

  group('samenvoegen', () {
    test('dezelfde plaat uit drie bronnen wordt één regel met drie merkjes', () {
      final uit = mergeDiscography([
        [_dz('Thriller', datum: '1982-11-30', cover: 'dz.jpg', tracks: 9)],
        [_mb('Thriller', datum: '1982-11-30')],
        [_dg('Thriller', datum: '1982')],
      ]);
      expect(uit, hasLength(1));
      expect(uit.first.sources, {DiscoSource.deezer, DiscoSource.musicbrainz, DiscoSource.discogs});
      expect(uit.first.refs.keys, hasLength(3), reason: 'elke bron houdt zijn eigen verwijzing');
    });

    test('de rijkste waarde wint, niet de laatste', () {
      final uit = mergeDiscography([
        [_mb('Thriller', datum: '1982-11-30')],
        [_dz('Thriller', datum: '2001-10-16', cover: 'dz.jpg', tracks: 9)],
      ]);
      expect(uit.first.cover, 'dz.jpg', reason: 'een hoes die er is verslaat null');
      expect(uit.first.trackCount, 9);
      expect(uit.first.firstDate, '1982-11-30',
          reason: 'Deezer geeft bij een heruitgave de heruitgavedatum; de plaat hoort op zijn eigen jaar');
    });

    test('DE test: de uitkomst hangt niet af van de volgorde waarin bronnen binnenkomen', () {
      // Hierop rust dat de pagina Deezer meteen toont en de rest erachteraan invult. Is samenvoegen
      // niet commutatief, dan verspringt de lijst terwijl je ernaar kijkt.
      final dz = [_dz('Thriller', datum: '2001-10-16', cover: 'dz.jpg', tracks: 9)];
      final mb = [_mb('Thriller', datum: '1982-11-30')];
      final dg = [_dg('Thriller', datum: '1982', cover: 'dg.jpg')];

      final heen = mergeDiscography([dz, mb, dg]).first;
      final terug = mergeDiscography([dg, mb, dz]).first;

      expect(terug.firstDate, heen.firstDate);
      expect(terug.trackCount, heen.trackCount);
      expect(terug.sources, heen.sources);
      expect(terug.title, heen.title);
      expect(terug.kind, heen.kind);
    });

    test('twee keer dezelfde lijst geeft geen tweede regel', () {
      final een = [_dz('Bad', datum: '1987-08-31')];
      expect(mergeDiscography([een, een]), hasLength(1));
    });

    test('een bron die "overig" zegt degradeert een album niet', () {
      final uit = mergeDiscography([
        [_mb('Off The Wall', kind: RecordKind.other)],
        [_dz('Off The Wall')],
      ]);
      expect(uit.first.kind, RecordKind.album);
    });
  });

  group('waarmee wordt hij geopend', () {
    test('Deezer eerst, want alleen die tak haalt een tracklijst in één verzoek', () {
      final alles = mergeDiscography([
        [_dz('Thriller', id: 42)],
        [_mb('Thriller')],
        [_dg('Thriller', id: 7)],
      ]).first;
      expect(alles.openRef!.source, CatalogSource.deezer);
      expect(alles.toCatalogAlbum().id, 42);

      final zonderDz = mergeDiscography([
        [_mb('Thriller')],
        [_dg('Thriller', id: 7)],
      ]).first;
      expect(zonderDz.openRef!.source, CatalogSource.musicbrainzGroup);

      final alleenDg = mergeDiscography([
        [_dg('Thriller', id: 7)]
      ]).first;
      expect(alleenDg.openRef!.source, CatalogSource.discogsMaster);
      expect(alleenDg.toCatalogAlbum().id, 0, reason: 'geen verzonnen Deezer-id voor een Discogs-plaat');
    });
  });

  group('sorteren', () {
    final lijst = [
      _dz('Zonder datum'),
      _dz('Oud', datum: '1979-08-10'),
      _dz('Nieuw', datum: '2021-11-19'),
      DiscoRelease(title: 'Een single', kind: RecordKind.single, firstDate: '1983-01-02'),
      DiscoRelease(title: 'Een verzamelaar', kind: RecordKind.compilation, firstDate: '2003-11-17'),
    ];

    test('op datum: nieuwste eerst, ongedateerd achteraan', () {
      final uit = sortDiscography(lijst, DiscoSort.datum, {});
      expect(uit.first.title, 'Nieuw');
      expect(uit.last.title, 'Zonder datum',
          reason: 'een lege datum is niet het jaar nul en hoort niet bovenaan');
    });

    test('op bezit: wat je hebt bovenaan, daarbinnen op datum', () {
      final bezit = {discoKey('Oud')};
      final uit = sortDiscography(lijst, DiscoSort.bezit, bezit);
      expect(uit.first.title, 'Oud');
    });

    test('de derde stand is alfabetisch, want het type bepaalt nu het blok', () {
      // Binnen een blok staat alles al van hetzelfde soort; nog eens op type sorteren zou niets doen.
      // Alfabetisch is dan het bruikbare antwoord: een plaat terugvinden waarvan je de naam weet.
      final uit = sortDiscography(lijst, DiscoSort.type, {}).map((r) => r.title).toList();
      final gesorteerd = [...uit]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      expect(uit, gesorteerd);
    });

    test('elke sortering is TOTAAL, dus de lijst springt niet', () {
      // Twee regels met dezelfde datum moeten elke keer in dezelfde volgorde komen, anders wisselen ze
      // van plek zodra er een bron bij komt.
      final gelijk = [
        _dz('Bravo', datum: '1990-01-01'),
        _dz('Alfa', datum: '1990-01-01'),
      ];
      for (final op in DiscoSort.values) {
        final een = sortDiscography(gelijk, op, {}).map((r) => r.title).toList();
        final twee = sortDiscography(gelijk.reversed.toList(), op, {}).map((r) => r.title).toList();
        expect(twee, een, reason: 'sortering $op moet onafhankelijk zijn van de aanvoervolgorde');
      }
    });

    test('leeg en één blijven heel', () {
      for (final op in DiscoSort.values) {
        expect(sortDiscography([], op, {}), isEmpty);
        expect(sortDiscography([_dz('Solo')], op, {}), hasLength(1));
      }
    });
  });
}
