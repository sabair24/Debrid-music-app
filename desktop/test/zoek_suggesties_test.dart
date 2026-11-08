import 'dart:async';
import 'dart:io';

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/zoek_geheugen.dart';
import 'package:debridmusic/zoek_suggesties.dart';
import 'package:flutter_test/flutter_test.dart';

/// Suggesties terwijl je typt (Saber, 08-11-2026): wat er in het paneel komt, in welke volgorde, en dat het woord uit de
/// bibliotheek meegaat naar Online zoeken.
Track nr(String artiest, String album, String titel) =>
    Track(path: 'D:/m/$artiest/$album/$titel.flac', title: titel, artist: artiest, album: album, trackNo: 1, isFlac: true);

Album plaat(String artiest, String titel, List<String> nummers, {bool single = false}) =>
    Album(titel, artiest, [for (final n in nummers) nr(artiest, titel, n)], isSingle: single);

final bib = [
  plaat('Khaled', 'Sahra', ['Aïcha', 'Lillah']),
  plaat('Khaled', "N'Ssi N'Ssi", ['Bakhta', 'Serbi Serbi']),
  plaat('Rihanna', 'Loud', ['Only Girl', 'California King Bed']),
  plaat('Beyoncé', 'I Am... Sasha Fierce', ['Halo', 'Single Ladies']),
  plaat('Adele', '21', ['Rolling in the Deep', 'Someone Like You']),
  plaat('Daft Punk', 'Discovery', ['One More Time', 'Harder Better Faster Stronger']),
  plaat('Backstreet Boys', "Backstreet's Back", ["Everybody (Backstreet's Back)"]),
  plaat('Niels Destadsbader', 'Vuur en vlam', ['Vuur en vlam'], single: true),
];

OnlineTreffers deezer({List<String> artiesten = const [], List<(String, String)> albums = const [], List<(String, String)> nummers = const []}) =>
    OnlineTreffers(
      [for (final (i, a) in artiesten.indexed) CatalogArtist(i + 1, a, 'https://cdn-images.dzcdn.net/images/artist/x/250x250-0.jpg', 3)],
      [
        for (final (i, a) in albums.indexed)
          CatalogAlbumHit(CatalogAlbum(i + 1, a.$2, 'https://cdn-images.dzcdn.net/images/cover/x/500x500-0.jpg', '2019-01-01', 10, 'album'), a.$1)
      ],
      [for (final n in nummers) CatalogTrackHit(n.$2, n.$1, 'https://cdn-images.dzcdn.net/images/cover/y/250x250-0.jpg')],
    );

List<String> titels(Iterable<Suggestie> l) => [for (final s in l) s.titel];

void main() {
  final index = EigenIndex.van(bib);

  group('hoe goed iets past', () {
    test('precies, begin, woordbegin, ergens, en een letter fout', () {
      expect(trefScore('khaled', 'khaled'), 1);
      expect(trefScore('khaled', 'kha'), .9);
      expect(trefScore('dj khaled', 'kha'), .8);
      expect(trefScore('wiz khalifa', 'kha'), .8);
      expect(trefScore('rihanna', 'han'), .5);
      expect(trefScore('rihanna', 'rihana'), .4);
      expect(trefScore('rihanna', 'zzz'), 0);
    });

    test('een typfout telt pas vanaf vier letters: bij "kha" is alles ruis', () {
      expect(trefScore('kya', 'kha'), 0);
      expect(trefScore('khaled', 'khle'), .4, reason: 'vier letters, een weg');
    });

    test('op één letter na: erbij, weg, anders, omgewisseld; twee is te veel', () {
      expect(opEenLetterNa('rihanna', 'rihana'), isTrue);
      expect(opEenLetterNa('rihana', 'rihanna'), isTrue);
      expect(opEenLetterNa('adele', 'adala'), isFalse);
      expect(opEenLetterNa('adele', 'adelo'), isTrue);
      expect(opEenLetterNa('stromae', 'stormae'), isTrue);
      expect(opEenLetterNa('abcd', 'badc'), isFalse);
    });

    test('een typfout met een andere eerste letter is een ander woord', () {
      expect(beginLijktOp('hallo', 'gallo'), isFalse);
      expect(beginLijktOp('rihanna', 'rihan'), isTrue);
    });

    test('artiest en titel door elkaar: elk woord moet ergens beginnen', () {
      expect(woordenPassen('get lucky', 'daft punk', 'daft get'), .7);
      expect(woordenPassen('get lucky', 'daft punk', 'daft zzz'), 0);
      expect(woordenPassen('get lucky', 'daft punk', 'daft'), 0, reason: 'een woord is gewoon trefScore');
    });
  });

  group('je eigen bibliotheek', () {
    test('Khaled, zijn platen en nummers', () {
      final uit = eigenSuggesties(index, 'kha');
      expect(titels(uit.where((s) => s.soort == SuggestieSoort.artiest)), ['Khaled']);
      expect(titels(uit.where((s) => s.soort == SuggestieSoort.album)), containsAll(['Sahra', "N'Ssi N'Ssi"]));
      expect(titels(uit.where((s) => s.soort == SuggestieSoort.nummer)), containsAll(['Aïcha', 'Bakhta']));
      expect(uit.every((s) => s.eigen), isTrue);
    });

    test('een accent en een apostrof zitten niet in de weg', () {
      expect(titels(eigenSuggesties(index, 'beyonce')), contains('Beyoncé'));
      expect(titels(eigenSuggesties(index, 'aicha')), contains('Aïcha'));
      expect(titels(eigenSuggesties(index, 'backstreets')), contains("Backstreet's Back"));
    });

    test('een letter fout vindt hem toch, alleen als precies te weinig gaf', () {
      expect(titels(eigenSuggesties(index, 'rihana')), contains('Rihanna'));
      // "Halo" past precies; er komt geen "Hallo"-achtige ruis bij zolang het niet nodig is.
      final halo = eigenSuggesties(EigenIndex.van([...bib, plaat('X', 'Y', ['Halo 2', 'Halo 3', 'Halo 4', 'Hallo'])]), 'halo');
      expect(titels(halo), isNot(contains('Hallo')));
    });

    test('een losse single is geen plaat, wel een nummer', () {
      final uit = eigenSuggesties(index, 'vuur');
      expect(uit.where((s) => s.soort == SuggestieSoort.album), isEmpty);
      expect(titels(uit.where((s) => s.soort == SuggestieSoort.nummer)), ['Vuur en vlam']);
    });

    test('een rij weet waar hij bij hoort', () {
      final n = eigenSuggesties(index, 'halo').firstWhere((s) => s.soort == SuggestieSoort.nummer);
      expect(n.track!.title, 'Halo');
      expect(n.album!.title, 'I Am... Sasha Fierce');
    });

    test('20.000 nummers doorzoeken blijft ruim binnen één letter', () {
      final groot = EigenIndex.van([
        for (var i = 0; i < 2000; i++) plaat('Artiest $i', 'Plaat $i', [for (var k = 0; k < 10; k++) 'Nummer $i $k']),
      ]);
      final klok = Stopwatch()..start();
      for (final q in ['n', 'nu', 'num', 'numm', 'nummr', 'nummer 19', 'zzzzz']) {
        eigenSuggesties(groot, q);
      }
      expect(klok.elapsedMilliseconds, lessThan(1500), reason: 'zeven rondes op de testmachine');
    });
  });

  group('mengen: beste treffer eerst', () {
    test('wat het best past staat bovenaan, ook als je het niet hebt', () {
      final uit = mengSuggesties(
        eigenSuggesties(index, 'kha'),
        onlineSuggesties(deezer(artiesten: ['Kha', 'DJ Khaled', 'Khaled']), 'kha'),
      );
      final artiesten = uit.firstWhere((g) => g.soort == SuggestieSoort.artiest).rijen;
      expect(artiesten.first.titel, 'Kha', reason: 'precies wat je typte, en je hebt hem niet: Saber koos beste treffer eerst');
      expect(artiesten.first.eigen, isFalse);
    });

    test('bij gelijke stand gaat jouw kopie voor', () {
      final uit = mengSuggesties(
        eigenSuggesties(index, 'adele'),
        onlineSuggesties(deezer(artiesten: ['Adele']), 'adele'),
      );
      final a = uit.firstWhere((g) => g.soort == SuggestieSoort.artiest).rijen;
      expect(a, hasLength(1), reason: 'wat in allebei zit, is één rij');
      expect(a.single.eigen, isTrue);
      expect(a.single.beeldUrl, isNotNull, reason: 'de foto van Deezer blijft erbij voor als de jouwe er niet is');
    });

    test('twee verschillende nummers die even goed passen: dat van jou staat boven', () {
      final uit = mengSuggesties(
        eigenSuggesties(index, 'halo'),
        onlineSuggesties(deezer(nummers: [('Iemand Anders', 'Halo')]), 'halo'),
      );
      final n = uit.firstWhere((g) => g.soort == SuggestieSoort.nummer).rijen;
      expect([for (final s in n) s.onder], ['Beyoncé', 'Iemand Anders']);
      expect(n.first.eigen, isTrue);
    });

    test('DJ Khaled en Khaled blijven twee rijen, en Khaled staat bovenaan', () {
      final uit = mengSuggesties(
        eigenSuggesties(index, 'khaled'),
        onlineSuggesties(deezer(artiesten: ['DJ Khaled', 'Khaled']), 'khaled'),
      );
      final a = uit.firstWhere((g) => g.soort == SuggestieSoort.artiest).rijen;
      expect(titels(a), ['Khaled', 'DJ Khaled']);
      expect(a.first.eigen, isTrue);
      expect(a.last.eigen, isFalse);
    });

    test('dezelfde plaat en hetzelfde nummer met een andere schrijfwijze zijn één rij', () {
      final uit = mengSuggesties(
        eigenSuggesties(index, 'rolling'),
        onlineSuggesties(deezer(nummers: [('ADELE', 'Rolling in the Deep')]), 'rolling'),
      );
      expect(uit.firstWhere((g) => g.soort == SuggestieSoort.nummer).rijen, hasLength(1));
    });

    test('bij "halo" gaan de nummers boven de artiesten', () {
      final uit = mengSuggesties(
        eigenSuggesties(index, 'halo'),
        onlineSuggesties(deezer(artiesten: ['Halogen']), 'halo'),
      );
      expect(uit.first.soort, SuggestieSoort.nummer);
    });

    test('bij gelijke stand blijft de volgorde artiesten, albums, nummers', () {
      final uit = mengSuggesties(const [], onlineSuggesties(deezer(artiesten: ['Sade'], albums: [('Sade', 'Sade')], nummers: [('Sade', 'Sade')]), 'sade'));
      expect([for (final g in uit) g.soort], [SuggestieSoort.artiest, SuggestieSoort.album, SuggestieSoort.nummer]);
    });

    test('per soort niet meer dan er past', () {
      final uit = mengSuggesties(const [], onlineSuggesties(deezer(artiesten: ['A1', 'A2', 'A3', 'A4', 'A5', 'A6']), 'a'));
      expect(uit.single.rijen, hasLength(4));
    });

    test('wat Deezer vindt op een typfout blijft staan, onderaan', () {
      final uit = onlineSuggesties(deezer(artiesten: ['Rihanna']), 'rhnna');
      expect(uit.single.score, greaterThan(0));
      expect(uit.single.score, lessThan(.4));
    });
  });

  group('de kleine hoes', () {
    test('Deezer maakt elke maat; een ander adres blijft staan', () {
      expect(kleinDeezerBeeld('https://cdn-images.dzcdn.net/images/cover/ab/500x500-000000-80-0-0.jpg'),
          'https://cdn-images.dzcdn.net/images/cover/ab/120x120-000000-80-0-0.jpg');
      expect(kleinDeezerBeeld('https://i.discogs.com/a/500x500-x.jpg'), 'https://i.discogs.com/a/500x500-x.jpg');
      expect(kleinDeezerBeeld(null), isNull);
    });
  });

  group('oplichten', () {
    String licht(String tekst, String q) => [for (final (a, z) in oplichtDelen(tekst, q)) tekst.substring(a, z)].join('|');

    test('de letters zoals ze er staan, op een woordbegin als dat kan', () {
      expect(licht('Khaled', 'kha'), 'Kha');
      expect(licht('Wiz Khalifa', 'kha'), 'Kha');
      expect(licht('Beyoncé', 'beyonce'), 'Beyoncé');
      expect(licht('Aïcha', 'aic'), 'Aïc');
      expect(licht('Mashka', 'ka'), 'ka');
      expect(licht('Daft Punk', 'punk daft'), 'Daft|Punk');
      expect(licht('Khaled', 'zzz'), '');
    });
  });

  group('laatste zoekopdrachten', () {
    test('de laatste vijf, de nieuwste bovenaan, zonder dubbele', () {
      final r = ZoekRecent();
      for (final w in ['een', 'twee', 'drie', 'vier', 'vijf', 'zes']) {
        r.voegToe(w);
      }
      expect(r.lijst, ['zes', 'vijf', 'vier', 'drie', 'twee']);
      r.voegToe('DRIE');
      expect(r.lijst, ['DRIE', 'zes', 'vijf', 'vier', 'twee']);
    });

    test('één letter is geen zoekopdracht; wissen werkt', () {
      final r = ZoekRecent();
      r.voegToe(' a ');
      expect(r.lijst, isEmpty);
      r.voegToe('adele');
      r.wis('adele');
      expect(r.lijst, isEmpty);
    });

    test('overleeft een herstart, en een kapot bestand is een lege lijst', () {
      final map = Directory.systemTemp.createTempSync('zoek_recent');
      addTearDown(() => map.deleteSync(recursive: true));
      final pad = '${map.path}/zoek_recent.json';
      ZoekRecent(bestand: () => pad).voegToe('khaled');
      expect(ZoekRecent(bestand: () => pad).lijst, ['khaled']);
      File(pad).writeAsStringSync('{kapot');
      expect(ZoekRecent(bestand: () => pad).lijst, isEmpty);
    });
  });

  group('terwijl je typt', () {
    late List<String> gevraagd;
    late Map<String, Completer<OnlineTreffers?>> open;

    SuggestieBron bron() {
      gevraagd = [];
      open = {};
      return SuggestieBron(
        albums: () => bib,
        online: (q) {
          gevraagd.add(q);
          return (open[q] = Completer<OnlineTreffers?>()).future;
        },
        eigenPauze: const Duration(milliseconds: 1),
        onlinePauze: const Duration(milliseconds: 20),
      );
    }

    Future<void> wacht([int ms = 40]) => Future<void>.delayed(Duration(milliseconds: ms));

    test('je eigen bibliotheek is er vóór Deezer antwoordt', () async {
      final b = bron();
      addTearDown(b.dispose);
      b.zet('khaled');
      await wacht();
      expect(gevraagd, ['khaled']);
      expect(b.onlineBezig, isTrue);
      expect(titels(b.groepen.expand((g) => g.rijen)), contains('Khaled'));
    });

    test('wie doortypt, vraagt Deezer één keer', () async {
      final b = bron();
      addTearDown(b.dispose);
      for (final q in ['k', 'kh', 'kha', 'khal', 'khale', 'khaled']) {
        b.zet(q);
        await wacht(3);
      }
      await wacht();
      expect(gevraagd, ['khaled']);
    });

    test('één letter gaat niet naar Deezer', () async {
      final b = bron();
      addTearDown(b.dispose);
      b.zet('k');
      await wacht();
      expect(gevraagd, isEmpty);
      expect(b.onlineBezig, isFalse);
    });

    test('een laat antwoord op wat je niet meer typt, wordt weggegooid', () async {
      final b = bron();
      addTearDown(b.dispose);
      b.zet('adele');
      await wacht();
      b.zet('sade');
      await wacht();
      open['sade']!.complete(deezer(artiesten: ['Sade']));
      await wacht(1);
      open['adele']!.complete(deezer(artiesten: ['Adele Online']));
      await wacht(1);
      expect(titels(b.groepen.expand((g) => g.rijen)), contains('Sade'));
      expect(titels(b.groepen.expand((g) => g.rijen)), isNot(contains('Adele Online')));
    });

    test('Deezer stuk: je eigen rijen blijven staan, en er is niets meer bezig', () async {
      final b = bron();
      addTearDown(b.dispose);
      b.zet('adele');
      await wacht();
      open['adele']!.completeError(Exception('geen net'));
      await wacht(1);
      expect(b.onlineBezig, isFalse);
      expect(titels(b.groepen.expand((g) => g.rijen)), contains('Adele'));
    });

    test('wissen en opnieuw typen kost geen tweede vraag', () async {
      final b = bron();
      addTearDown(b.dispose);
      b.zet('adele');
      await wacht();
      open['adele']!.complete(deezer(artiesten: ['Adele Tribute']));
      await wacht(1);
      b.zet('');
      expect(b.groepen, isEmpty);
      b.zet('adele');
      await wacht();
      expect(gevraagd, ['adele']);
      expect(titels(b.groepen.expand((g) => g.rijen)), contains('Adele Tribute'));
    });

    test('een herbouwde bibliotheek wordt meteen doorzocht', () async {
      final lijsten = [
        [plaat('Oud', 'Plaat', ['Nummer'])],
        [plaat('Nieuwe Naam', 'Plaat', ['Nummer'])],
      ];
      var i = 0;
      final b = SuggestieBron(
          albums: () => lijsten[i], online: (_) async => null, eigenPauze: const Duration(milliseconds: 1), onlinePauze: const Duration(milliseconds: 1));
      addTearDown(b.dispose);
      b.zet('nieuwe');
      await wacht(10);
      expect(b.groepen, isEmpty);
      i = 1;
      b.zet('nieuwe naam');
      await wacht(10);
      expect(titels(b.groepen.expand((g) => g.rijen)), contains('Nieuwe Naam'));
    });
  });

  group('het woord gaat mee naar Online zoeken', () {
    test('op Bladeren, met dat woord, zonder de lijsten van de vorige keer, en maar één keer', () {
      ZoekGeheugen.tab = ZoekTab.tidal;
      ZoekGeheugen.vraag = 'de vorige keer';
      ZoekGeheugen.artiesten = [CatalogArtist(1, 'Oud', null, 0)];
      ZoekGeheugen.startMet('khalid');
      expect(ZoekGeheugen.tab, ZoekTab.bladeren);
      expect(ZoekGeheugen.vraag, 'khalid');
      expect(ZoekGeheugen.artiesten, isEmpty);
      expect(ZoekGeheugen.neemStart(), 'khalid');
      expect(ZoekGeheugen.neemStart(), isNull, reason: 'een sectiewissel later mag niet opnieuw zoeken');
    });
  });

  group('de bedrading in main.dart', () {
    final bron = File('lib/main.dart').readAsStringSync();

    test('de knop bij Niets gevonden neemt je woord mee, in Albums en in Tracks', () {
      expect(bron, contains("Online zoeken kijkt verder dan je eigen kast.',\n            knop: 'Online zoeken',\n            opKnop: () => zoekOnlineMet?.call(_q),"));
      expect(bron, contains("knop: query.isEmpty ? null : 'Online zoeken',\n        opKnop: query.isEmpty ? null : () => zoekOnlineMet?.call(query),"));
    });

    test('Online zoeken begint vanzelf als het woord meekwam', () {
      final begin = bron.indexOf('class _OnlineSearchScreenState');
      final init = bron.substring(bron.indexOf('void initState()', begin), bron.indexOf('Future<void> _searchTidal', begin));
      expect(init, contains('if (ZoekGeheugen.neemStart() != null) {'));
      expect(init, contains('unawaited(_search());'));
    });

    test('suggesties gaan nooit naar Soulseek of TIDAL', () {
      final catalog = File('lib/catalog.dart').readAsStringSync();
      final begin = catalog.indexOf('Future<OnlineTreffers?> suggesties(');
      final lijf = catalog.substring(begin, catalog.indexOf('return OnlineTreffers(', begin));
      expect(begin, greaterThan(0));
      expect(lijf, isNot(contains('oulseek')));
      expect(lijf, isNot(contains('tidal')));
      expect(lijf, isNot(contains('autocomplete')), reason: '56 KB per vraag');
      expect(RegExp(r'online: \(q\) => [_A-Za-z()]*\.?suggesties\(q\)').allMatches(bron), hasLength(greaterThanOrEqualTo(3)));
    });

    test('een eigen nummer gaat langs de tik-regels van de app, net als een online nummer', () {
      final begin = bron.indexOf('void kiesSuggestie(');
      final lijf = bron.substring(begin, bron.indexOf('\n}\n', begin));
      expect(lijf, contains('speelGetikt(context, album.tracks'));
      expect(lijf, contains('speelGetiktNieuw(context,'));
    });

    test('het woord landt niet op de losse TIDAL-pagina, en een draai geeft geen dubbele sleutel', () {
      expect(bron, contains('if (widget.tidalVraag == null) onlineVeldPlek = _veldPlek;'));
      expect(bron, contains('if (onlineVeldPlek == _veldPlek) onlineVeldPlek = null;'));
      expect(bron, isNot(contains('final kOnlineZoekVeld = GlobalKey')));
    });
  });
}
