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

    test('"Comp" is Discogs\' afkorting van Compilation — en de enige die hij gebruikt', () {
      // De duurste meting van deze ronde. Op `/artists/{id}/releases` komt `Compilation` VOLUIT nul
      // keer voor en `Comp` 1711 keer, over 12093 regels. Deze functie zocht alleen het hele woord,
      // dus die regel heeft daar nooit één keer geraakt: zeventienhonderd verzamelaars stonden
      // tussen de albums. Saber wees "All About The Police" aan — `Cass, Album, Comp`.
      expect(kindFromDiscogs('Cass, Album, Comp'), RecordKind.compilation);
      expect(kindFromDiscogs('2xCDr, Album, Comp'), RecordKind.compilation);
      expect(kindFromDiscogs('CD, Comp'), RecordKind.compilation);
      expect(kindFromDiscogs('7xLP + Box, Comp'), RecordKind.compilation);
      // En het hele woord blijft werken, want de zoek-endpoint schrijft het wél uit.
      expect(kindFromDiscogs('Vinyl, LP, Album, Compilation'), RecordKind.compilation);
      // Op velden en niet op deelreeksen: "comp" zit ook in "compact".
      expect(kindFromDiscogs('Compact Disc, Album'), isNot(RecordKind.compilation));
    });

    /// Film- en dvd-uitgaves horen niet in een discografie, "wel als er officieel een live album
    /// music is". Die tweede helft is de reden dat er op de DRAGER gekeken wordt: een concert
    /// bestaat vaak als dvd én als plaat, en dan hoort de plaat te blijven.
    test('een dvd is geen plaat — maar een cd met een dvd erbij wel', () {
      // De echte formaatteksten uit Sabers Discogs-cache van Michael Jackson.
      expect(kindFromDiscogs('DVD-V, PAL'), RecordKind.video);
      expect(kindFromDiscogs('3xDVD, Comp, NTSC'), RecordKind.video);
      expect(kindFromDiscogs('2xDVD-V'), RecordKind.video);
      expect(kindFromDiscogs('DVDr, Promo'), RecordKind.video);
      expect(kindFromDiscogs('UMD, Ltd'), RecordKind.video);
      expect(kindFromDiscogs('Blu-ray, Album'), RecordKind.video,
          reason: 'ook als het woord "Album" er staat — de drager is beeld');

      expect(kindFromDiscogs('CD, Comp, RE + DVD-V, Comp, RE, NTSC'), isNot(RecordKind.video),
          reason: 'een cd-verzamelaar met een dvd erbij is nog steeds een cd');
      expect(kindFromDiscogs('CD, Comp + DVD-V, PAL'), isNot(RecordKind.video));
      expect(kindFromDiscogs('CD, Album'), RecordKind.album);
    });

    /// Radioplaten: geperst om uitgezonden te worden, nooit verkocht, en daarom met een etiketscan
    /// als hoes. Bij The Police waren dat twintig van de drieëndertig "albums".
    test('een transcriptieplaat is radio, geen album', () {
      // De echte formaatteksten uit de Discogs-cache van The Police.
      expect(kindFromDiscogs('LP, Transcription'), RecordKind.uitzending);
      expect(kindFromDiscogs('LP, Promo, Transcription'), RecordKind.uitzending);
      expect(kindFromDiscogs('LP, Transcription, Ser'), RecordKind.uitzending);
      expect(kindFromDiscogs('Vinyl, LP, Transcription'), RecordKind.uitzending);
      expect(kindFromDiscogs('Reel, 2tr Stereo, 7" Reel, Transcription'), RecordKind.uitzending);
      expect(kindFromMb('Broadcast', const []), RecordKind.uitzending);

      // Promo telt NIET mee. GEMETEN: 1593 regels dragen Promo zonder Transcription, en dat zijn
      // grotendeels gewone promopersingen van echte singles.
      expect(kindFromDiscogs('CD, Single, Promo'), RecordKind.single);
      expect(kindFromDiscogs('LP, Ltd, Promo'), RecordKind.album);
    });

    test('DE BOTSING: een radiopersing mag de echte plaat niet verbergen', () {
      // GEMETEN: van de 182 transcriptieregels dragen er vier een titel die óók zonder dat kenmerk
      // bestaat — "Elegantly Wasted" van INXS is een echt album waarvan ook een radiopersing is.
      // Daarom staat `uitzending` ONDER de geluidsuitspraken in de uitspraakrang.
      final radio = DiscoRelease(title: 'Elegantly Wasted', kind: RecordKind.uitzending);
      final plaat = _dz('Elegantly Wasted');
      expect(radio.mergedWith(plaat).kind, RecordKind.album);
      expect(plaat.mergedWith(radio).kind, RecordKind.album, reason: 'en in beide volgordes');

      // Maar kent alleen Discogs hem, en alleen als transcriptie, dan verdwijnt hij.
      expect(
          zeefDiscografie([
            DiscoRelease(
                title: 'BBC Rock Hour #207',
                kind: RecordKind.uitzending,
                cover: 'http://h/r.jpg'),
          ]).rijen,
          isEmpty);
    });

    test('de twee vallen: VCD bevat "CD", en DVD-Audio is geluid', () {
      expect(kindFromDiscogs('VCD, Comp, Promo'), RecordKind.video,
          reason: 'op deelreeksen zou een video-cd voor een gewone cd doorgaan');
      expect(alleenVideo('DVD-A, Album'), isFalse, reason: 'dvd-AUDIO is een plaat');
      expect(alleenVideo('Blu-ray Audio'), isFalse);
      expect(alleenVideo('CD, Album'), isFalse);
      expect(alleenVideo(''), isFalse, reason: 'geen formaat is geen uitspraak');
    });

    test('de tweede lijst van MusicBrainz bepaalt de indeling, niet alleen bij een verzamelaar', () {
      // Dit stond hier ANDERSOM — "een livealbum blijft een album; alleen compilatie verandert de
      // indeling" — en dat was precies de klacht: "HIStory Manila 1996", "Bad Live In Yokohama" en
      // "Heal the World Tour 92" stonden tussen de studioplaten. MusicBrainz zet dat gewoon in
      // `secondary-types`; de app las er één woord van. Gemeten over de 333 releasegroepen van
      // Michael Jackson: Live 32, Remix 59, Interview 3, Demo 5.
      expect(kindFromMb('Album', ['Compilation']), RecordKind.compilation);
      expect(kindFromMb('Album', []), RecordKind.album);
      expect(kindFromMb('Album', ['Live']), RecordKind.live);
      expect(kindFromMb('Album', ['Remix']), RecordKind.remix);
      expect(kindFromMb('Single', ['DJ-mix']), RecordKind.remix);
      expect(kindFromMb('Album', ['Demo']), RecordKind.demo);
      expect(kindFromMb('Album', ['Mixtape/Street']), RecordKind.demo);
      expect(kindFromMb('Album', ['Interview']), RecordKind.gesproken);
      expect(kindFromMb('Album', ['Spokenword']), RecordKind.gesproken);
      expect(kindFromMb('Album', ['Live', 'Compilation']), RecordKind.compilation,
          reason: 'een livecompilatie hoort bij de verzamelaars');
      expect(kindFromMb('Album', ['Soundtrack']), RecordKind.album,
          reason: 'een soundtrack die de artiest zélf maakte is een plaat, geen ruis — en de '
              'samengeraapte dragen bij MusicBrainz óók "Compilation"');
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

    test('de standaardstand zet de OUDSTE plaat vooraan, en ongedateerd blijft achteraan', () {
      // Saber vroeg om oud→nieuw als stand waarin de pagina opengaat. De tweede helft is de val: een
      // kale tekstvergelijking op '' zet ongedateerde regels bij oplopend juist VOORAAN, en dan
      // begint de discografie met de platen waarvan niemand het jaar weet.
      final uit = sortDiscography(lijst, DiscoSort.datumOud, {});
      expect(uit.first.title, 'Oud');
      expect(uit.last.title, 'Zonder datum');
    });

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

  /// Een UITSPRAAK van de ene bron moet een schouderophalen van de andere overleven.
  ///
  /// Dezelfde val als bij de verzamelaar hierboven, maar nu vier keer zo breed. `kindRank` is een
  /// LEESVOLGORDE en album staat daar op 0 — dus zou een Discogs-formaat dat "LP, Album" zegt élk
  /// livealbum van MusicBrainz terugtrekken tussen de studioplaten. En "Album" op een Discogs-lp is
  /// geen uitspraak: dat staat óók op de lp van een concertplaat.
  group('een uitspraak van de ene bron overleeft de andere', () {
    test('MusicBrainz zegt live, Discogs zegt alleen "Album"', () {
      final live = _mb('Live At Wembley', kind: RecordKind.live);
      final dg = _dg('Live At Wembley');
      expect(live.mergedWith(dg).kind, RecordKind.live);
      expect(dg.mergedWith(live).kind, RecordKind.live, reason: 'en in beide volgordes');
    });

    test('remix, demo en gesproken houden het ook vol tegen een kaal album', () {
      for (final soort in [RecordKind.remix, RecordKind.demo, RecordKind.gesproken]) {
        final uitspraak = _mb('Iets', kind: soort);
        final vorm = _dg('Iets');
        expect(uitspraak.mergedWith(vorm).kind, soort);
        expect(vorm.mergedWith(uitspraak).kind, soort);
      }
    });

    test('DE HELFT DIE MOET BLIJVEN: een concert-dvd die óók als plaat bestaat, blijft', () {
      // "wel als er officieel een Live album music is". Kent MusicBrainz de titel als livealbum en
      // Discogs alleen als dvd, dan bestaat die plaat — en dan is de dvd niet het hele verhaal.
      final plaat = _mb('Live In Bucharest', kind: RecordKind.live);
      final schijf = DiscoRelease(title: 'Live In Bucharest', kind: RecordKind.video);
      expect(plaat.mergedWith(schijf).kind, RecordKind.live);
      expect(schijf.mergedWith(plaat).kind, RecordKind.live, reason: 'en in beide volgordes');

      // Maar kent alleen Discogs hem, en alleen als dvd, dan is het beeld.
      expect(zeefDiscografie([
        DiscoRelease(title: 'Iets Op Dvd', kind: RecordKind.video, cover: 'http://h/v.jpg'),
      ]).rijen, isEmpty);
    });

    test('een gewoon album verslaat video ook', () {
      final dvd = DiscoRelease(title: 'X', kind: RecordKind.video);
      final plaat = _dz('X');
      expect(dvd.mergedWith(plaat).kind, RecordKind.album);
      expect(plaat.mergedWith(dvd).kind, RecordKind.album);
    });

    test('een livecompilatie is een verzamelaar', () {
      final live = _mb('Best Of Live', kind: RecordKind.live);
      final verzamel = DiscoRelease(title: 'Best Of Live', kind: RecordKind.compilation);
      expect(live.mergedWith(verzamel).kind, RecordKind.compilation);
      expect(verzamel.mergedWith(live).kind, RecordKind.compilation);
    });

    test('"overig" blijft een afwezigheid en verliest van alles', () {
      for (final soort in RecordKind.values) {
        if (soort == RecordKind.other) continue;
        final iets = _mb('X', kind: soort);
        final niets = DiscoRelease(title: 'X', kind: RecordKind.other);
        expect(iets.mergedWith(niets).kind, soort);
        expect(niets.mergedWith(iets).kind, soort);
      }
    });

    test('samenvoegen blijft commutatief voor ELK paar soorten', () {
      // De eis waar de hele pagina op rust: de drie bronnen komen op willekeurige momenten binnen.
      for (final a in RecordKind.values) {
        for (final b in RecordKind.values) {
          final x = DiscoRelease(title: 'Zelfde', kind: a);
          final y = DiscoRelease(title: 'Zelfde', kind: b);
          expect(x.mergedWith(y).kind, y.mergedWith(x).kind,
              reason: 'samenvoegen van $a en $b hangt van de volgorde af');
        }
      }
    });
  });

  /// Heruitgaves ZONDER haakjes — "Bad 25", "Thriller 40".
  ///
  /// En vooral de grendel eromheen. Zonder die grendel vouwt "Chicago 17" weg, en dat is een
  /// studioalbum: een verborgen plaat merk je nooit, een dubbele regel zie je meteen.
  group('heruitgaves zonder haakjes', () {
    List<String> blokVan(List<DiscoRelease> rijen, RecordKind soort) => [
          for (final r in vouwHeruitgaves(rijen))
            if (r.blok == soort) r.title
        ];

    test('"Thriller 40" verhuist naar Andere uitgaves, want "Thriller" staat er ook', () {
      final rijen = [_dz('Thriller', datum: '1982'), _dz('Thriller 40', datum: '2022')];
      expect(blokVan(rijen, RecordKind.album), ['Thriller']);
      expect(blokVan(rijen, RecordKind.albumVersie), ['Thriller 40']);
    });

    test('zonder het kale album blijft het een album op zichzelf', () {
      expect(blokVan([_dz('Thriller 40', datum: '2022')], RecordKind.album), ['Thriller 40']);
    });

    test('"Bad 25th Anniversary" vouwt op het WOORD, ook zonder jaartallen', () {
      final rijen = [_dz('Bad'), _dz('Bad 25th Anniversary')];
      expect(blokVan(rijen, RecordKind.albumVersie), ['Bad 25th Anniversary']);
    });

    test('"Chicago 17" naast "Chicago" blijft een album — het jaar klopt niet met het getal', () {
      final rijen = [_dz('Chicago', datum: '1970'), _dz('Chicago 17', datum: '1984')];
      expect(blokVan(rijen, RecordKind.album), containsAll(['Chicago', 'Chicago 17']));
      expect(blokVan(rijen, RecordKind.albumVersie), isEmpty);
    });

    test('een klein getal is nooit een jubileum', () {
      final rijen = [_dz('Peter Gabriel', datum: '1977'), _dz('Peter Gabriel 3', datum: '1980')];
      expect(blokVan(rijen, RecordKind.albumVersie), isEmpty);
    });

    test('"30 ans de succes" naast "30" blijft een eigen plaat', () {
      final rijen = [_dz('30'), _dz('30 ans de succes')];
      expect(blokVan(rijen, RecordKind.albumVersie), isEmpty);
    });

    test('de uitkomst hangt niet af van de aanvoervolgorde, en twee keer vouwen doet niets meer', () {
      final rijen = [_dz('Thriller', datum: '1982'), _dz('Thriller 40', datum: '2022')];
      final een = vouwHeruitgaves(rijen).map((r) => '${r.title}=${r.kind}').toList()..sort();
      final twee = vouwHeruitgaves(rijen.reversed.toList()).map((r) => '${r.title}=${r.kind}').toList()
        ..sort();
      expect(twee, een);
      final nogmaals = vouwHeruitgaves(vouwHeruitgaves(rijen)).map((r) => '${r.title}=${r.kind}').toList()
        ..sort();
      expect(nogmaals, een);
    });
  });

  /// Wat de pagina weglaat, en of ze dat toegeeft.
  ///
  /// Deze zeef haalt bij Michael Jackson 153 van de 252 regels weg. Dat mag — Saber vroeg erom —
  /// maar niet stilzwijgend: de telling die onder de sectiekop komt moet kloppen, en "toon alles"
  /// moet écht alles terugzetten. Anders is het geen filter maar een verlies.
  group('wat de pagina weglaat, en of ze dat toegeeft', () {
    final rijen = [
      _dz('Met hoes', cover: 'http://h/1.jpg'),
      _dz('Zonder hoes'),
      DiscoRelease(title: 'Rariteit', kind: RecordKind.other, cover: 'http://h/2.jpg'),
      DiscoRelease(title: 'Praatplaat', kind: RecordKind.gesproken, cover: 'http://h/3.jpg'),
      DiscoRelease(title: 'Concert', kind: RecordKind.live, cover: 'http://h/4.jpg'),
      DiscoRelease(title: 'Remixen', kind: RecordKind.remix, cover: 'http://h/5.jpg'),
    ];

    test('overig, demo en gesproken komen er niet in; live en remix wél', () {
      final z = zeefDiscografie(rijen);
      expect(z.rijen.map((r) => r.title), ['Met hoes', 'Concert', 'Remixen']);
    });

    test('de telling klopt: verborgen + getoond = alles', () {
      final z = zeefDiscografie(rijen);
      expect(z.rijen.length + z.verborgen, rijen.length);
      expect(z.zonderHoes, 1);
      expect(z.perSoort[RecordKind.other], 1);
      expect(z.perSoort[RecordKind.gesproken], 1);
    });

    test('toonAlles geeft alles terug en telt nog steeds wat er wég zou vallen', () {
      final z = zeefDiscografie(rijen, toonAlles: true);
      expect(z.rijen.length, rijen.length);
      expect(z.verborgen, 3, reason: 'de knop hoort te kunnen zeggen wat hij terugzet');
    });

    test('DE VAL: een regel die pas ná vulHoezenAan een hoes heeft, blijft staan', () {
      // "Bad" (1987) draagt in de samenvoeging geen hoes en krijgt er pas een uit de Discogs-sweep.
      // Zeven vóór het aanvullen gooit precies de platen weg die het hardst op de pagina horen.
      final voor = [_dz('Bad', datum: '1987')];
      expect(zeefDiscografie(voor).rijen, isEmpty, reason: 'zonder hoes valt hij af');
      final na = vulHoezenAan(voor, {discoKey('Bad'): 'http://h/bad.jpg'});
      expect(zeefDiscografie(na).rijen.single.title, 'Bad');
    });

    test('zonder Discogs-token blijft de hoesregel uit', () {
      // Geen token betekent geen zoeksweep en dus geen hoezen om mee aan te vullen. Zou de regel dan
      // tóch draaien, dan verdwijnt élke plaat die alleen MusicBrainz kent — bij deze artiest zijn
      // dat Off The Wall, Dangerous en Invincible.
      final z = zeefDiscografie(rijen, zeefHoezen: false);
      expect(z.rijen.map((r) => r.title), contains('Zonder hoes'));
      expect(z.zonderHoes, 0);
    });
  });
}
