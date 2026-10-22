/// Stijl en tijdvak, volgens meer dan één bron.
///
/// Saber op 26-09-2026: *"dit is gelimiteerd aan deezer, maar moet combinatie zijn van AI, discogs
/// eventueel, the audiodatabase."* De getallen hieronder zijn wat Discogs en TheAudioDB die dag echt
/// antwoordden, voor de radio vanaf "Freak Out" van 2 Fabiola.
library;

import 'dart:io';

import 'package:debridmusic/radiostijl.dart';
import 'package:flutter_test/flutter_test.dart';

const Zaadstijl freakOut = (familie: Stijlfamilie.dans, jaar: 1997);

void main() {
  group('welke familie een genre is', () {
    test('DE KERN: wat TheAudioDB zei', () {
      expect(familieVan('Euro Dance'), Stijlfamilie.dans, reason: '2 Fabiola, Cappella');
      expect(familieVan('Dance'), Stijlfamilie.dans, reason: 'Milk Inc., Kate Ryan');
      expect(familieVan('Pop'), Stijlfamilie.popsoul, reason: 'Niels Destadsbader');
      expect(familieVan('R&B'), Stijlfamilie.popsoul, reason: 'Donna Summer');
    });

    test('DE KERN: wat Discogs zei', () {
      expect(familieVan('Electronic'), Stijlfamilie.dans);
      expect(familieVan('Euro House'), Stijlfamilie.dans);
      expect(familieVan('Eurodance'), Stijlfamilie.dans);
      expect(familieVan('Funk / Soul'), Stijlfamilie.popsoul);
      expect(familieVan('Hip Hop'), Stijlfamilie.hiphop);
    });

    test('DE VAL: "Euro Pop" is dans, geen pop — het specifieke woord gaat voor', () {
      expect(familieVan('Europop'), Stijlfamilie.dans);
    });

    test('DE GRENS: wat niets zegt, zegt niets', () {
      expect(familieVan('Stage & Screen'), isNull);
      expect(familieVan(''), isNull);
      expect(familieVan(null), isNull);
    });
  });

  group('het oordeel', () {
    test('DE KERN: het jaar weert niet meer (Saber, 22-10-2026) — de stijl beslist', () {
      // Discogs zette "De Wereld Draait Voor Jou" (met Regi) bij Electronic/Eurodance, in 2021. Een dance-label
      // is dance; of het in de sfeer past, zegt het model.
      expect(keurStijl(freakOut, (families: {Stijlfamilie.dans}, jaar: 2021)).mag, isTrue);
    });

    test('DE KERN: binnen het tijdvak en de stijl mag het', () {
      expect(keurStijl(freakOut, (families: {Stijlfamilie.dans}, jaar: 1994)).mag, isTrue,
          reason: 'Cappella — Move On Baby');
    });

    test('DE KERN: geen enkele bron in de stijl van het zaad, dan valt het af', () {
      expect(keurStijl(freakOut, (families: {Stijlfamilie.popsoul}, jaar: 1998)).mag, isFalse);
    });

    test('DE VAL: één bron die ja zegt is genoeg', () {
      // TheAudioDB mag een eurodance-act "Pop" noemen; zegt Discogs Electronic, dan hoort hij erbij.
      expect(keurStijl(freakOut, (families: {Stijlfamilie.popsoul, Stijlfamilie.dans}, jaar: 1998)).mag,
          isTrue);
    });

    test('DE VAL: niets bekend is geen reden om te weigeren', () {
      final o = keurStijl(freakOut, (families: const <Stijlfamilie>{}, jaar: null));
      expect(o.mag, isTrue);
      expect(o.waarom, 'niets bekend');
    });

    test('DE GRENS: zonder zaadjaar telt het tijdvak niet, zonder zaadstijl de stijl niet', () {
      expect(keurStijl((familie: null, jaar: null), (families: {Stijlfamilie.rock}, jaar: 1970)).mag,
          isTrue);
    });
  });

  group('rock is niet één ding (kwaliteitscontrole van 26-09-2026)', () {
    test('DE KERN: grunge en alternatief tegenover hardrock en ballads', () {
      expect(rockTak(['Grunge', 'Alternative Rock']), 'alternatief');
      expect(rockTak(['Hard Rock', 'Arena Rock']), 'klassiek');
      expect(rockTak(['Pop Rock', 'Ballad']), 'klassiek');
      expect(rockTak(['Euro House']), isNull);
      expect(meerderheidTak(['alternatief', 'klassiek', 'alternatief', null]), 'alternatief');
      expect(meerderheidTak(['alternatief', 'klassiek']), isNull);
    });

    test('DE KERN: een Nirvana-radio weert Bon Jovi en houdt Pearl Jam', () async {
      final map = Directory.systemTemp.createTempSync('dm_rock_');
      addTearDown(() {
        try {
          map.deleteSync(recursive: true);
        } catch (_) {}
      });
      final b = Stijlboek(
        bestand: File('${map.path}${Platform.pathSeparator}radiostijl.json'),
        audioDbGenre: (_) async => 'Rock',
        discogsNummer: (a, t) async => switch (a) {
          'Bon Jovi' => [(jaar: 1992, genres: ['Rock'], stijlen: ['Hard Rock', 'Arena Rock'])],
          'Pearl Jam' => [(jaar: 1991, genres: ['Rock'], stijlen: ['Grunge', 'Alternative Rock'])],
          _ => const <DiscogsUitgave>[],
        },
      );
      const zaad = (familie: Stijlfamilie.rock, jaar: 1991);
      expect((await b.keur('Bon Jovi', 'Keep the Faith', zaad, zaadTak: 'alternatief')).mag, isFalse);
      expect((await b.keur('Pearl Jam', 'Alive', zaad, zaadTak: 'alternatief')).mag, isTrue);
      expect((await b.keur('Onbekend', 'Iets', zaad, zaadTak: 'alternatief')).mag, isTrue,
          reason: 'weet Discogs de tak niet, dan geen nee');
    });

    test('DE KERN: een bootleg telt niet', () {
      expect(isBootleg(['CD', 'Album', 'Unofficial Release']), isTrue);
      expect(isBootleg(['CD', 'Maxi-Single']), isFalse);
    });
  });

  group('welke Discogs-uitgave van deze artiest is', () {
    test('DE KERN: een hele naam, geen deel — Leon Sash is Sash! niet', () {
      expect(uitgaveVanArtiest('Leon Sash - I Remember Newport', 'Sash!'), isFalse);
      expect(uitgaveVanArtiest('Sash! - Stay', 'Sash!'), isTrue);
      expect(uitgaveVanArtiest('The Jam - Snap!', 'Snap!'), isFalse);
    });

    test('DE VAL: Discogs\' sterretje en naamgenootnummer tellen als dezelfde naam', () {
      expect(uitgaveVanArtiest('Snap* - The Power', 'Snap!'), isTrue);
      expect(uitgaveVanArtiest('Snap* Featuring Einstein (2) - The Power 96', 'Snap!'), isTrue);
      expect(uitgaveVanArtiest('Oasis (2) - Wonderwall', 'Oasis'), isTrue);
      expect(uitgaveVanArtiest('Niels Destadsbader & Regi - De Wereld Draait Voor Jou', 'Regi'), isTrue);
    });

    test('DE GRENS: een verzamelaar is van niemand', () {
      expect(uitgaveVanArtiest('Various - Hyper Rave 6', 'Snap!'), isFalse);
      expect(uitgaveVanArtiest('Snap! - The Power', ''), isFalse);
    });

    test('DE KERN: de titel zoals Discogs hem vindt', () {
      expect(kaleTitel("It's My Life (2011 Version)"), "It's My Life");
      expect(kaleTitel('Mr. Vain - Radio Edit'), 'Mr. Vain');
      expect(kaleTitel('Freak Out'), 'Freak Out');
    });
  });

  group('de feiten uit de uitgaven', () {
    test('DE KERN: het vroegste jaar — een heruitgave zegt niets over het nummer', () {
      expect(vroegsteJaar([2015, 1994, null, 2003, 0]), 1994);
      expect(vroegsteJaar(const []), isNull);
    });

    test('DE KERN: de meest genoemde stijlen eerst', () {
      expect(meesteStijlen(['Trance', 'Euro House', 'Euro House', 'House', 'Euro House', 'Trance']),
          ['Euro House', 'Trance', 'House']);
    });
  });

  group('het stijlboek', () {
    late Directory map;
    late List<String> audioDb, discogs;

    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_stijl_');
      audioDb = [];
      discogs = [];
    });
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    Stijlboek boek({
      Map<String, String?> genres = const {},
      Map<String, List<DiscogsUitgave>?> nummers = const {},
      bool audioDbStuk = false,
    }) =>
        Stijlboek(
          bestand: File('${map.path}${Platform.pathSeparator}radiostijl.json'),
          audioDbGenre: (a) async {
            audioDb.add(a);
            if (audioDbStuk) throw const SocketException('geen net');
            return genres[a];
          },
          discogsNummer: (a, t) async {
            discogs.add('$a|$t');
            return nummers['$a|$t'] ?? const [];
          },
        );

    test('DE KERN: zonder jaargrens houdt de stijl Niels buiten een Freak Out-radio', () async {
      // Discogs: één uitgave Electronic/Eurodance, één Pop — geen meerderheid. Dan beslist TheAudioDB: Pop.
      final b = boek(genres: {'Niels Destadsbader': 'Pop'}, nummers: {
        'Niels Destadsbader|De Wereld Draait Voor Jou': [
          (jaar: 2021, genres: ['Electronic'], stijlen: ['Eurodance']),
          (jaar: 2021, genres: ['Pop'], stijlen: const []),
        ],
      });
      final o = await b.keur('Niels Destadsbader', 'De Wereld Draait Voor Jou', freakOut);
      expect(o.mag, isFalse);
      expect(o.waarom, contains('popsoul'));
    });

    test('DE KERN: disco blijft eruit — Discogs zegt Funk / Soul, niet het jaar 1979', () async {
      // Donna Summer: Discogs zegt Funk / Soul en Disco. Dat is geen dance.
      final b = boek(nummers: {
        'Donna Summer|Hot Stuff': [(jaar: 1979, genres: ['Funk / Soul'], stijlen: ['Disco'])],
      });
      expect((await b.keur('Donna Summer', 'Hot Stuff', freakOut)).mag, isFalse);
    });

    test('DE KERN: noemt Discogs de stijl niet, dan beslist TheAudioDB mee', () async {
      final b = boek(genres: {'Niels': 'Pop', 'Kate Ryan': 'Dance'});
      expect((await b.keur('Niels', 'Iets', freakOut)).mag, isFalse);
      expect((await b.keur('Kate Ryan', 'Scream for More', freakOut)).mag, isTrue);
      expect(audioDb, ['Niels', 'Kate Ryan']);
    });

    test('DE VAL: wat al bekend is wordt niet opnieuw gevraagd — ook niet na een herstart', () async {
      await boek(genres: {'Kate Ryan': 'Dance'}).keur('Kate Ryan', 'Scream for More', freakOut);
      audioDb.clear();
      discogs.clear();
      final opnieuw = boek(genres: {'Kate Ryan': 'Dance'});
      expect((await opnieuw.keur('Kate Ryan', 'Scream for More', freakOut)).mag, isTrue);
      expect(audioDb, isEmpty);
      expect(discogs, isEmpty);
    });

    test('DE KERN: twee keuringen tegelijk stellen één vraag', () async {
      // Review van 26-09-2026: na een time-out stuurde de keuring een TWEEDE vraag achter in de rij.
      final b = boek(nummers: {
        'Cappella|Move On Baby': [(jaar: 1994, genres: ['Electronic'], stijlen: ['Euro House'])],
      });
      await Future.wait([b.nummer('Cappella', 'Move On Baby'), b.nummer('Cappella', 'Move On Baby')]);
      expect(discogs, ['Cappella|Move On Baby']);
    });

    test('DE VAL: geen antwoord van Discogs wordt niet onthouden als "niets bekend"', () async {
      var keer = 0;
      final b = Stijlboek(
        bestand: File('${map.path}${Platform.pathSeparator}radiostijl.json'),
        audioDbGenre: (_) async => null,
        discogsNummer: (a, t) async {
          keer++;
          return keer == 1 ? null : [(jaar: 1994, genres: ['Electronic'], stijlen: const <String>[])];
        },
      );
      expect((await b.nummer('Cappella', 'Move On Baby')).jaar, isNull);
      expect((await b.nummer('Cappella', 'Move On Baby')).jaar, 1994,
          reason: 'de tweede keer opnieuw gevraagd, want de eerste keer was een storing');
    });

    test('DE VAL: een storing wordt niet onthouden als "geen genre"', () async {
      final stuk = boek(audioDbStuk: true);
      expect(await stuk.artiest('Kate Ryan'), isNull);
      final heel = boek(genres: {'Kate Ryan': 'Dance'});
      expect(await heel.artiest('Kate Ryan'), Stijlfamilie.dans,
          reason: 'anders blijft Kate Ryan voor altijd "onbekend" na één keer geen net');
    });

    test('DE KERN: het zaad — het vroegste van tag en Discogs, en de stijl eerst van het nummer', () async {
      // Je tag zegt 2012 (de verzamelaar waar je het van hebt), Discogs 1997.
      final b = boek(genres: {'2 Fabiola': 'Pop'}, nummers: {
        "2 Fabiola|Freak Out ('97 Remix)": [(jaar: 1997, genres: ['Electronic'], stijlen: ['Euro House'])],
      });
      expect(await b.zaad('2 Fabiola', "Freak Out ('97 Remix)", eigenJaar: 2012),
          (familie: Stijlfamilie.dans, jaar: 1997));
      expect(audioDb, isEmpty,
          reason: 'Discogs noemde het nummer Electronic; TheAudioDB\'s "Pop" voor de artiest telt dan niet');
    });

    test('DE VAL: kent Discogs het zaad niet, dan de artiest bij TheAudioDB en je eigen jaar', () async {
      final b = boek(genres: {'Aqua': 'Pop'});
      expect(await b.zaad('Aqua', 'Iets Onbekends', eigenJaar: 1997), (familie: Stijlfamilie.popsoul, jaar: 1997));
    });

    test('DE KERN: een gelijke stand tussen families zegt niets, een meerderheid wel', () {
      expect(meerderheid([
        {Stijlfamilie.dans},
        {Stijlfamilie.popsoul},
        {Stijlfamilie.popsoul, Stijlfamilie.rock},
      ]), {Stijlfamilie.popsoul});
      expect(meerderheid([{Stijlfamilie.dans}, {Stijlfamilie.popsoul}]), isEmpty);
      expect(meerderheid(const []), isEmpty);
    });

    test('DE KERN: één remixsingle maakt Wannabe geen dansmuziek', () async {
      // Zoals Discogs het gaf: negen uitgaven Pop, één met Electronic erbij.
      final b = boek(genres: {'Spice Girls': 'Pop'}, nummers: {
        'Spice Girls|Wannabe': [
          for (var i = 0; i < 9; i++) (jaar: 1996, genres: ['Pop'], stijlen: const <String>[]),
          (jaar: 1996, genres: ['Electronic', 'Pop'], stijlen: ['House']),
        ],
      });
      expect((await b.keur('Spice Girls', 'Wannabe', freakOut)).mag, isFalse);
    });

    test('DE GRENS: zonder eigen jaar komt het jaar van Discogs, en de stijlnamen voor het model',
        () async {
      final b = boek(nummers: {
        '2 Fabiola|Freak Out': [
          (jaar: 1997, genres: ['Electronic'], stijlen: ['Euro House', 'Trance']),
          (jaar: 1998, genres: ['Electronic'], stijlen: ['Euro House']),
        ],
      });
      expect(await b.zaad('2 Fabiola', 'Freak Out'), (familie: Stijlfamilie.dans, jaar: 1997));
      expect(await b.stijlnamen('2 Fabiola', 'Freak Out'), ['Euro House', 'Trance']);
    });
  });

  // Saber, 22-10-2026: "nergens een grens van jaren vanaf 1950 tot heden" — "maar natuurlijk eurodance is geen
  // disco e, dit moet wel accurater blijven". De gevallen hieronder zijn wat het tijdvak tot dan weerde in
  // radio.log, en wat Discogs die dag van hun uitgaven zei.
  group('geen jaargrens, wel het genre', () {
    const niels = (familie: Stijlfamilie.popsoul, jaar: 2026);
    const sade = (familie: Stijlfamilie.jazz, jaar: 1992);

    test('DE KERN: het jaar weert niets meer — Clouseau bij Niels, Etta James bij Sade', () {
      expect(keurStijl(niels, (families: {Stijlfamilie.popsoul}, jaar: 2001)).mag, isTrue, reason: 'Clouseau');
      expect(keurStijl(niels, (families: {Stijlfamilie.popsoul}, jaar: 1991)).mag, isTrue, reason: 'Margriet Hermans');
      expect(keurStijl(sade, (families: {Stijlfamilie.popsoul}, jaar: 1960)).mag, isTrue, reason: 'Etta James');
      expect(keurStijl(freakOut, (families: const <Stijlfamilie>{}, jaar: 1955)).mag, isTrue);
      expect(keurStijl(freakOut, (families: const <Stijlfamilie>{}, jaar: 2026)).mag, isTrue);
    });

    test('DE VAL: disco blijft uit een eurodance-radio — op de familie, niet op 1979', () {
      expect(keurStijl(freakOut, (families: {Stijlfamilie.popsoul}, jaar: 1979)).mag, isFalse,
          reason: 'Donna Summer — Hot Stuff: Discogs Funk / Soul, Disco');
    });

    // Per tak op hoeveel uitgaven, zoals Discogs het op 22-10-2026 gaf.
    List<DiscogsUitgave> uitgaven(List<List<String>> stijlen) => [
          for (final s in stijlen) (jaar: null, genres: const ['Electronic'], stijlen: s)
        ];

    test('de danstak van een nummer: specifiek eerst', () {
      expect(danstakkenVan(['Euro House', 'House']), {'eurodance', 'house'});
      expect(danstakkenVan(['Hardstyle']), {'hardstyle'});
      expect(danstakkenVan(['Electro House', 'Progressive House']), {'edm', 'house'});
      expect(danstakkenVan(['Happy Hardcore']), {'eurodance'});
      expect(danstakkenVan(['Hardcore']), {'hardstyle'});
      expect(danstakkenVan(['Synth-pop']), isEmpty);
      final fabiola = danstakTelling(uitgaven([
        ['Euro House', 'Trance'],
        ['Euro House'],
        ['Eurodance', 'Happy Hardcore'],
        ['House'],
      ]));
      expect(fabiola, {'eurodance': 3, 'trance': 1, 'house': 1, '_': 4});
      expect(danstakVanZaad(fabiola), 'eurodance');
      expect(danstakVanZaad(const {'_': 0}), isNull);
    });

    test('DE KERN: hardstyle en EDM uit een eurodance-radio; de rave van de jaren negentig blijft', () {
      bool past(List<List<String>> s) => danstakPast('eurodance', danstakTelling(uitgaven(s)));
      expect(past([['Hardstyle'], ['Hardstyle']]), isFalse, reason: 'Da Tweekaz — Supa Dupa Fly');
      expect(past([['Electro House']]), isFalse, reason: 'Ummet Ozcan — Eins Zwei');
      expect(past([['Trance'], ['Trance', 'Hard Trance'], ['Trance'], ['House']]), isTrue,
          reason: 'Brooklyn Bounce — Bass, Beats & Melody');
      expect(past([for (var i = 0; i < 10; i++) ['Techno', 'Hardcore'], ['Disco']]), isTrue,
          reason: 'L.A. Style — James Brown Is Dead: techno op 10 van 10');
      expect(past([['Euro House'], ['Electro House'], ['Hardstyle']]), isTrue,
          reason: 'één remix maakt een eurodancenummer geen EDM: eurodance staat op een derde');
      expect(past(const []), isTrue, reason: 'Discogs weet niets: dan beslist het model');
      expect(danstakPast('edm', danstakTelling(uitgaven([['Euro House', 'Eurodance']]))), isFalse,
          reason: 'en andersom: een EDM-radio is geen eurodance-radio');
    });

    test('het stijlboek: de danstak van het zaad weert hardstyle — behalve wat het model zelf koos', () async {
      final map = Directory.systemTemp.createTempSync('dm_danstak_');
      addTearDown(() {
        try {
          map.deleteSync(recursive: true);
        } catch (_) {}
      });
      final b = Stijlboek(
        bestand: File('${map.path}${Platform.pathSeparator}radiostijl.json'),
        audioDbGenre: (_) async => null,
        discogsNummer: (a, t) async => switch (a) {
          '2 Fabiola' => uitgaven([['Euro House'], ['Euro House', 'Happy Hardcore'], ['Trance']]),
          'Da Tweekaz' => [for (final s in [['Hardstyle'], ['Hardstyle']]) (jaar: 2022, genres: const ['Electronic'], stijlen: s)],
          _ => uitgaven([['Trance'], ['Trance', 'House']]),
        },
      );
      await b.nummer('2 Fabiola', 'Freak Out');
      final zaad = danstakVanZaad((await b.danstak('2 Fabiola', 'Freak Out'))!);
      expect(zaad, 'eurodance');
      final nee = await b.keur('Da Tweekaz', 'Supa Dupa Fly', freakOut, zaadDanstak: zaad);
      expect(nee.mag, isFalse);
      expect(nee.waarom, 'dance, maar hardstyle en niet eurodance');
      expect((await b.keur('Da Tweekaz', 'Supa Dupa Fly', freakOut, zaadDanstak: zaad, doorModel: true)).mag, isTrue);
      expect((await b.keur('Brooklyn Bounce', 'Bass, Beats & Melody', freakOut, zaadDanstak: zaad)).mag, isTrue);
      expect((await b.keur('Da Tweekaz', 'Supa Dupa Fly', freakOut)).mag, isTrue, reason: 'zonder zaadtak geen tak');
    });

    test('aangesloten: de radiokeuring geeft de danstak van het zaad mee', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main.contains('        zaadDanstak: danstak,\n'), isTrue);
      expect(main.contains('    final danstak = await _zaadDanstak;\n'), isTrue);
      expect(main.contains('        if (z.familie != Stijlfamilie.dans || t == null) return null;\n'), isTrue);
    });
  });
}
