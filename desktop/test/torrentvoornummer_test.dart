// Torrents onder een nummer: alleen wat erbij hoort, de rest verborgen met een reden.
//
// Gemeld op 15-10-2026 onder Céline Dion — "Bonjour, Pardon, Merci (Bon Entendeur Remix)": RuTracker
// vond op de hele vraag niets, zocht ruimer op "Céline Dion" en alle 46 torrents die de lijst haalden
// waren andere platen. De namen hieronder zijn letterlijk die van die dag.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/rutracker.dart';
import 'package:debridmusic/search.dart';
import 'package:debridmusic/torbox.dart';
import 'package:debridmusic/torrentvoornummer.dart';
import 'package:flutter_test/flutter_test.dart';

const _remix = 'Bonjour, Pardon, Merci (Bon Entendeur Remix)';

TorrentPast _remixOordeel(String naam, {List<String>? bestanden}) => torrentVoorNummer(
      rutrackerTitelSchoon(naam),
      artiest: 'Céline Dion',
      titel: _remix,
      seconden: 175,
      album: _remix,
      jaar: 2026,
      bestanden: bestanden,
    );

/// De 46 namen van 15-10-2026, zoals RuTracker ze stuurde (met de getallen voor letters).
const _celine = [
  '(Soundtrack, Score) [2LP] [24/192] Celine Dion – I Am: Celine Dion. Original Motion Picture Soundtrack - 2024, FLAC (image+.cue)',
  '[TR16][OF] Celine Dion - A New Day Has Come - 2002 (Pop) [Dolby Atmos]',
  '[TR24][OF] Celine Dion - The Very Best Of Celine Dion - 1999 (Pop)',
  '(Pop) [31 CD] C&#233;line Dion / Celine Dion / Collection (Singles) 31 CD-Releases (1990-2003), FLAC (tracks+.cue), lossless',
  '(Поп, Рок) A360 Media Music Special (68 номеров) (Elvis, Rolling Stones, Frank Sinatra, Michael Jackson, Stevie Nicks, Jimi Hendrix, Whitney Houston, Rush, The Beatles, Neil Diamond, Celine Dion, Pink Floyd, Ozzy Osbourne, Metallica ...) [2022-2025, PDF, ENG]',
  '[TR16][OF] Celine Dion - Taking Chances (Deluxe Edition) - 2007 (Pop) [Dolby Atmos]',
  "[TR16][OF] Celine Dion - S'il suffisait d'aimer - 1998 (Pop) [Dolby Atmos]",
  '(Pop) [LP] [1bit/5.6MHz] Celine Dion - My Love - 2024, DSD 128 (tracks)',
  '(Pop) C&#233;line Dion / Celine Dion / Collection (18 Albums, 36 Releases) [39 CD] - (1987-2019), FLAC (tracks+.cue), lossless',
  '[TR16][OF] Celine Dion - Falling Into You [Dolby Atmos] - 1996 (Pop)',
  '(Pop, Electronic, Funk / Soul) [CD] Celine Dion - Коллекция 6 CD (3 Albums + 3 Singles) (Japan Edition) - 1991-2008, FLAC (tracks+.cue), lossless',
  '[TR24][OF] Celine Dion - Love Again (Soundtrack from the Motion Picture) - 2023 (Pop)',
  '[TR16][OF] Celine Dion - These Are Special Times [Dolby Atmos] - 1998 / 2022 (Pop)',
  '[TR16][OF] Celine Dion - Loved Me Back to Life (Deluxe Version) - 2013 (Pop) [Dolby Atmos]',
  '[TR24][OF]Celine Dion - The Show Must Go On (Single) - 2016 (Pop)',
  "[TR16][OF] Celine Dion - D'eux - 1995 (Pop) [Dolby Atmos]",
  '[TR24][OF][FM] Celine Dion - I AM Celine Dion (Original Motion Picture Soundtrack) - 2024 (Pop)',
  '[TR16][OF] Celine Dion - Courage [Deluxe Edition] [Dolby Atmos] - 2019 / 2024 (Pop)',
  '(Pop) [CD] Celine Dion - I AM - Celine Dion (Original Motion Picture Soundtrack) - 2024 [Japan], FLAC (image+.cue), lossless',
  '[TR24][OF] Celine Dion - Unison - 1990 (Pop)',
  '[TR24][SACD-R] Celine Dion - All The Way... A Decade Of Song - 1999 (Pop)',
  '(Pop Ballads) [CD] Celine Dion - Celine Dion - Best Ballads (1996) - 1996, FLAC (image+.cue), lossless',
  '[TR16][OF] Celine Dion - 1 fille & 4 types - 2003 (Pop) [Dolby Atmos]',
  '[TR24][SACD-R] Celine Dion - Falling Into You - 1996 / 2015 (Pop)',
  "[TR16][OF] Celine Dion - D'elles - 2007 (Pop) [Dolby Atmos]",
  '(Pop) C&#233;line Dion / Celine Dion / Collection (9 Compilations, 15 Releases) [17 CD] - (1993-2018), FLAC (tracks+.cue), lossless',
  '[RM] [restored] [16/44] (Pop) Celine Dion - The Album Collection (Remastered Edition, 28.06.2023), APE (image+.cue), lossless',
  '[TR24][SACD-R] Celine Dion - A New Day Has Come - 2002 (Pop)',
  "[TR24][OF] Celine Dion - Hymne &#224; l'amour (Live aux Jeux Olympiques de Paris 2024) - 2024 (Pop)",
  '(Pop) [CD] C&#233;line Dion (Celine Dion) - Courage - 2019, FLAC (tracks+.cue), lossless',
  '(Vocal, Ballad) [CD] C&#233;line Dion / Celine Dion - Au C&#339;ur Du Stade / Au Coeur Du Stade - 1999 [Live album], FLAC (tracks+.cue), lossless',
  '[BR][SACD-R][OF] Celine Dion - All The Way... A Decade Of Song (Epic Records) - 1999 (Pop) Pure Audio',
  '(Pop) [CD] C&#233;line Dion / Celine Dion - En Concert - 1985 [Unofficial Release], FLAC (tracks+.cue), lossless',
  '(Pop | Classical) [WEB] The Messina Ensemble - Piano Strings Tribute To Celine Dion - 2004, FLAC (tracks), lossless',
  'Celine Dion - I Want You To Need Me (Thunderpuss Club Edit) Promo Only [2001, House, Tribal House, DVD]',
  '(Pop) [2xLP] [24/192] Celine Dion – Courage. Limited Edition, Ruby Red Vinyl - 2020, FLAC (image+.cue)',
  '(Pop) [CDM] Celine Dion - Immortality (Remixes) (Promo) - 1997, FLAC (tracks), lossless',
  "(Pop) [CD] C&#233;line Dion / Celine Dion - The Collector's Series, Volume One (BK 85148 / DIDP 101654) - 2000, FLAC (tracks+.cue), lossless",
  "(Pop) [CD] C&#233;line Dion / Celine Dion - C&#180;est pour vivre / C'est pour vivre (CNM013CD) - 1997, FLAC (tracks+.cue), lossless",
];

void main() {
  group('de remix van 15-10-2026', () {
    test('geen enkele van de torrents van die dag hoort erbij', () {
      final zichtbaar = [for (final n in _celine) if (_remixOordeel(n).zichtbaar) n];
      expect(zichtbaar, isEmpty);
    });

    test('verzamelingen die eindigen vóór 2026 kunnen hem niet dragen', () {
      expect(_remixOordeel(_celine[3]), TorrentPast.anders, reason: 'Collection (Singles) 1990-2003');
      expect(_remixOordeel(_celine[8]), TorrentPast.anders, reason: 'Collection 1987-2019');
      expect(_remixOordeel(_celine[10]), TorrentPast.anders, reason: 'Коллекция 1991-2008');
    });

    test('een torrent die de remix noemt staat er wel, ook met andere schrijfwijze', () {
      expect(_remixOordeel('Céline Dion - Bonjour, Pardon, Merci (Bon Entendeur Remix) - 2026 [WEB] FLAC'),
          TorrentPast.nummer);
      expect(_remixOordeel('Celine Dion - Bonjour Pardon Merci (Remixes) - 2026, FLAC (tracks)'),
          TorrentPast.nummer, reason: 'een remixpakket kan hem dragen');
    });

    test('maar het origineel als losse single noemt de remix niet', () {
      expect(_remixOordeel('Celine Dion - Bonjour, Pardon, Merci (Single) - 2026, FLAC'),
          TorrentPast.anders);
    });

    test('een discografie zonder einddatum blijft staan: dat valt niet uit te sluiten', () {
      expect(_remixOordeel('Céline Dion - Discography - FLAC'), TorrentPast.verzameling);
      expect(_remixOordeel('Celine Dion - Дискография (1981-2026), FLAC'), TorrentPast.verzameling);
    });
  });

  group('de bestandenlijst beslist', () {
    test('staat het nummer erin, dan bovenaan met een merkje', () {
      final p = _remixOordeel('Céline Dion - Collection (2026)', bestanden: [
        'Celine Dion - Singles 2026/01 Bonjour, Pardon, Merci.flac',
        'Celine Dion - Singles 2026/02 Bonjour, Pardon, Merci (Bon Entendeur Remix).flac',
      ]);
      expect(p, TorrentPast.bevat);
      expect(torrentMerk(p), '✓ bevat dit nummer');
    });

    test('staat het er niet in, dan weg — ook al noemt de naam een discografie', () {
      expect(
          _remixOordeel('Céline Dion - Discography', bestanden: [
            'Celine Dion - Courage/01 Lying Down.flac',
            'Celine Dion - Courage/02 Courage.flac',
          ]),
          TorrentPast.mist);
    });

    test('een vinylrip per kant zegt niets over titels — dan beslist de naam', () {
      // Zo stond de gecachte "I Am" bij TorBox: "01. Side A.flac". Een kant is geen nummer.
      final kanten = [
        'Celine Dion – I Am Celine Dion [LP] - 2024 (lossless)/01. Side A.flac',
        'Celine Dion – I Am Celine Dion [LP] - 2024 (lossless)/02. Side B.flac',
      ];
      expect(_remixOordeel('Celine Dion - Discography', bestanden: kanten), TorrentPast.verzameling);
      expect(_remixOordeel(_celine[0], bestanden: kanten), TorrentPast.anders);
    });

    test('een image met cue ook niet', () {
      expect(
          _remixOordeel('Celine Dion - Discography',
              bestanden: ['CD1/Celine Dion - Courage.flac', 'CD1/Celine Dion - Courage.cue']),
          TorrentPast.verzameling);
    });
  });

  group('een gewoon nummer van een album', () {
    TorrentPast hit(String naam) => torrentVoorNummer(rutrackerTitelSchoon(naam),
        artiest: 'Céline Dion',
        titel: 'My Heart Will Go On',
        album: "Let's Talk About Love",
        jaar: 1997);

    test('verzamelingen en best-ofs van na 1997 blijven staan', () {
      expect(hit(_celine[2]), TorrentPast.verzameling, reason: 'The Very Best Of - 1999');
      expect(hit(_celine[3]), TorrentPast.verzameling, reason: 'Collection (Singles) 1990-2003');
      expect(hit(_celine[8]), TorrentPast.verzameling, reason: 'Collection 1987-2019');
    });

    test('het album zelf bij naam', () {
      expect(hit("Celine Dion - Let's Talk About Love - 1997, FLAC (tracks+.cue)"), TorrentPast.album);
    });

    test('een ander album van dezelfde artiest niet', () {
      expect(hit(_celine[1]), TorrentPast.anders, reason: 'A New Day Has Come');
      expect(hit(_celine[29]), TorrentPast.anders, reason: 'Courage');
    });

    test('verzamelingen van vóór het nummer niet', () {
      expect(hit('Celine Dion - Collection (1981-1995), FLAC'), TorrentPast.anders);
    });

    test('een instrumentale versie is een ander nummer, tenzij je die zoekt', () {
      // Op de pc, 15-10-2026, onder "My Heart Will Go On".
      TorrentPast mhwgo(String naam, {String titel = 'My Heart Will Go On'}) =>
          torrentVoorNummer(naam, artiest: 'Céline Dion', titel: titel, album: "Let's Talk About Love", jaar: 1997);
      expect(mhwgo('Céline Dion - My Heart Will Go On (Instrumental).mp3'), TorrentPast.anders);
      expect(mhwgo('Céline Dion - My Heart Will Go On (Instrumental).mp3', titel: 'My Heart Will Go On (Instrumental)'),
          TorrentPast.nummer);
      expect(mhwgo('(Pop) Céline Dion / Celine Dion - My Heart Will Go On (Japan CDS) - 1997, APE (image+.cue), lossless'),
          TorrentPast.nummer);
      expect(mhwgo('(Pop/Dance) Celine Dion - My Heart Will Go On (Inc. Inpetto Mixes) CDM 2008, MP3 (tracks)'),
          TorrentPast.nummer, reason: 'een cd-single met mixen draagt het origineel meestal ook');
    });

    test('dezelfde titel van iemand anders is een ander nummer', () {
      TorrentPast courage(String naam) =>
          torrentVoorNummer(naam, artiest: 'Céline Dion', titel: 'Courage', album: 'Courage', jaar: 2019);
      expect(courage('Hollywood Undead - Courage - 2024, FLAC (tracks)'), TorrentPast.anders);
      expect(courage(rutrackerTitelSchoon(_celine[29])), TorrentPast.nummer);
    });
  });

  test('de volgorde: wat erin zit, dan het nummer, dan het album, dan verzamelingen — en verder stabiel', () {
    final lijst = ['v1', 'a1', 'n1', 'v2', 'b1', 'n2'];
    const oordeel = {
      'v1': TorrentPast.verzameling,
      'a1': TorrentPast.album,
      'n1': TorrentPast.nummer,
      'v2': TorrentPast.verzameling,
      'b1': TorrentPast.bevat,
      'n2': TorrentPast.nummer,
    };
    expect(opTorrentRang(lijst, (s) => oordeel[s]!), ['b1', 'n1', 'n2', 'a1', 'v1', 'v2']);
  });

  test('de regel boven de lijst zegt hoeveel en waarom', () {
    expect(verborgenTorrentsZin(46), '46 torrents verborgen — ze noemen dit nummer niet.');
    expect(verborgenTorrentsZin(1), '1 torrent verborgen — hij noemt dit nummer niet.');
    expect(verborgenTorrentsZin(3, mist: 3), '3 torrents verborgen — volgens TorBox zit dit nummer er niet in.');
    expect(verborgenTorrentsZin(5, mist: 2),
        '5 torrents verborgen: 3 noemen dit nummer niet, bij 2 zegt TorBox dat het er niet in zit.');
    expect(verborgenTorrentsZin(4, nummer: false), '4 torrents verborgen — ze noemen deze plaat niet.');
  });

  test('laatsteJaar leest bereiken en losse jaren', () {
    expect(laatsteJaar('Collection (Singles) 31 CD-Releases (1990-2003)'), 2003);
    expect(laatsteJaar('These Are Special Times - 1998 / 2022 (Pop)'), 2022);
    expect(laatsteJaar('Collector\'s Series (BK 85148 / DIDP 101654) - 2000'), 2000);
    expect(laatsteJaar('Discography'), isNull);
  });

  group('RuTracker-namen als gewone tekst', () {
    test('getallen worden letters', () {
      expect(rutrackerTitelSchoon('C&#233;line Dion'), 'Céline Dion');
      expect(rutrackerTitelSchoon("Hymne &#224; l'amour"), "Hymne à l'amour");
      expect(rutrackerTitelSchoon('Au C&#339;ur Du Stade'), 'Au Cœur Du Stade');
      expect(rutrackerTitelSchoon('&#x41;BBA'), 'ABBA');
    });
    test('de oude vormen blijven werken, en &amp; als laatste', () {
      expect(rutrackerTitelSchoon('<b>Simon &amp; Garfunkel</b> &#039;Live&#039;'), "Simon & Garfunkel 'Live'");
      expect(rutrackerTitelSchoon('&amp;#233;'), '&#233;');
    });
    test('onzin blijft staan zoals hij is', () {
      expect(rutrackerTitelSchoon('&#55296;'), '&#55296;');
    });
  });

  group('wat geen muziek is', () {
    test('VHS, DVD-remux, thuisvideo en tijdschriften', () {
      expect(isRommel('Celine Dion - Unison Home Video [1991, Pop, Soft Rock, VHSRip]'), isTrue);
      // Een VHS blijft beeld, ook als er een geluidsspoor bij genoemd wordt.
      expect(isRommel('Celine Dion - Taking Chances Tour [2009, Pop, VHSRip, MP3]'), isTrue);
      expect(isRommel('Celine Dion - Live In Memphis [1997, Pop, DVDRemux]'), isTrue);
      expect(isRommel(_celine[4]), isTrue, reason: 'PDF-tijdschriften');
    });
    test('maar een plaat met een PDF-boekje of een DVD-Audio met formaat blijft', () {
      expect(isRommel('Celine Dion - Courage - 2019, FLAC (tracks+.cue+log+PDF), lossless'), isFalse);
      expect(isRommel('Celine Dion - Falling Into You [DVD-Audio] DVDRemux 24/96 FLAC'), isFalse);
    });
  });

  test('TorBox: het antwoord met bestanden wordt hash → paden', () {
    final b = torboxBestandenUit({
      'success': true,
      'data': [
        {
          'name': 'Celine Dion – I Am Celine Dion [LP] - 2024 (lossless)',
          'hash': '94C0B5DA4B028F01BFCFF170016CE51F803C9FC7',
          'files': [
            {'id': 15, 'name': 'Celine Dion – I Am Celine Dion [LP] - 2024 (lossless)/01. Side A.flac', 'short_name': '01. Side A.flac'},
            {'id': 16, 'name': ''},
          ],
        },
        {'name': 'zonder bestanden', 'hash': 'aa'},
      ],
    });
    expect(b.keys, ['94c0b5da4b028f01bfcff170016ce51f803c9fc7']);
    expect(b.values.single, ['Celine Dion – I Am Celine Dion [LP] - 2024 (lossless)/01. Side A.flac']);
    expect(torboxBestandenUit(null), isEmpty);
  });

  group('het album zoeken met zijn opnamemerk', () {
    test('een haakje dat een andere opname noemt blijft staan', () {
      expect(DiscogsService.plainTitle(_remix), _remix);
      expect(DiscogsService.plainTitle('Blood On The Dance Floor (HIStory In The Mix)'),
          'Blood On The Dance Floor (HIStory In The Mix)');
      expect(DiscogsService.plainTitle('Trip on This (The Remixes)'), 'Trip on This (The Remixes)');
      expect(DiscogsService.plainTitle('Roots, Rock, Reggae (Live)'), 'Roots, Rock, Reggae (Live)');
    });

    test('een haakje dat dezelfde plaat aankleedt gaat er nog steeds af', () {
      expect(DiscogsService.plainTitle('Rumours (2004 Remaster)'), 'Rumours');
      expect(DiscogsService.plainTitle('Discovery (Deluxe Edition)'), 'Discovery');
      expect(DiscogsService.plainTitle('Fearless (Bonus Track Version)'), 'Fearless');
      expect(DiscogsService.plainTitle('Thriller (Original Motion Picture Soundtrack)'), 'Thriller');
    });

    test('het origineel is niet de remix, en de remix is zichzelf', () {
      expect(DiscogsService.titleScore('Céline Dion - Bonjour, Pardon, Merci', 'Céline Dion', _remix),
          lessThan(-2));
      expect(DiscogsService.titleScore('Céline Dion - Bonjour, Pardon, Merci (Bon Entendeur Remix)',
              'Céline Dion', _remix),
          greaterThan(0));
      expect(DiscogsService.zelfdeOpname(_remix, 'Bonjour, Pardon, Merci'), isFalse);
      expect(DiscogsService.zelfdeOpname(_remix, 'Bonjour, pardon, merci (Bon Entendeur remix)'), isTrue);
      expect(DiscogsService.zelfdeOpname('Rumours (2004 Remaster)', 'Rumours'), isTrue);
    });

    test('een strenge Discogs-vraag houdt het origineel ook tegen', () {
      final body = {
        'results': [
          {'master_id': 1, 'title': 'Céline Dion - Bonjour, Pardon, Merci', 'format': ['Vinyl', '7"']},
          {'master_id': 2, 'title': 'Céline Dion - Bonjour, Pardon, Merci (Bon Entendeur Remix)', 'format': ['File']},
        ],
      };
      expect(DiscogsService.mastersUit(body, 'Céline Dion', _remix), [2]);
      // Zonder merk blijft een strenge vraag alles houden, zoals altijd.
      expect(DiscogsService.mastersUit(body, 'Céline Dion', 'Bonjour, Pardon, Merci').first, 1);
    });

    test('de remix op Soulseek past op de looptijd van de remix, niet op die van het origineel', () {
      // soneo_app, 15-10-2026: "01 Bonjour, Pardon, Merci (Bon Entendeur Remix).flac", 2:51.
      const pad = r'@@music\Céline Dion\Bonjour, Pardon, Merci (Bon Entendeur Remix)\01 Bonjour, Pardon, Merci (Bon Entendeur Remix).flac';
      expect(fileOffersTitle(_remix, 175, 'Céline Dion', pad, 171, album: _remix), isTrue,
          reason: 'Deezer: 175 s');
      expect(fileOffersTitle(_remix, 190, 'Céline Dion', pad, 171, album: _remix), isFalse,
          reason: 'dit was het: 190 s van het origineel, 19 s ernaast');
    });

    test('de scans die onder de oude titel bewaard zijn, worden voor zo\'n album opnieuw gezocht', () {
      String oud(String album) =>
          sha1.convert(utf8.encode('art|v7|Céline Dion|$album|1|0||')).toString();
      expect(artCacheKey('Céline Dion', _remix, 1, null, null, const {}), isNot(oud(_remix)));
      // Een gewoon album houdt zijn bewaarde scans.
      expect(artCacheKey('Céline Dion', 'Courage', 1, null, null, const {}), oud('Courage'));
    });
  });

  group('aangesloten', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');

    test('de albumpagina neemt geen persing over die een andere opname beschrijft', () {
      expect(main, contains('DiscogsService.zelfdeOpname(widget.album.title, full?.title'));
    });

    test('de albumpagina kent het jaar ook als alleen Deezer het weet', () {
      // Gezien op de pc, 15-10-2026: zonder jaar bleven zes verzamelingen tot 2019 onder een remix van
      // 2026 staan. Een treffer uit "Online zoeken" draagt geen datum.
      expect(main, contains("_deezerJaar = int.tryParse(album?.year ?? '');"));
      expect('_officialYear ?? _deezerJaar ??'.allMatches(main).length, 2);
    });

    test('de lijst onder een nummer oordeelt, vraagt TorBox en verbergt met een reden', () {
      final start = main.indexOf('class _SourcesViewState');
      final eind = main.indexOf('TrackTags? get _trackAuthority', start);
      final bron = main.substring(start, eind);
      expect(bron, contains('online.bestandenVanGecacht('));
      expect(bron, contains('torrentVoorNummer(r.name'));
      expect(bron, contains('verborgenTorrentsZin('));
      expect(bron, contains('if (oordeel[r]!.zichtbaar) r'));
      expect(bron, contains('if (!oordeel[r]!.zichtbaar) r'), reason: 'de verborgen helft');
    });
  });
}
