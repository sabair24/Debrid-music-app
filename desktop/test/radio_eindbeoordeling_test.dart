/// Wat de eindbeoordeling van de radio op 26-09-2026 vond, en wat er sindsdien vastligt.
///
/// De radio kiest uit drie bronnen — Deezer, het taalmodel, Discogs en TheAudioDB als keuring — en
/// een laatste ronde langs alles vond negen plekken waar een regel die voor één voorbeeld gemaakt
/// was, een ander voorbeeld stil verkeerd deed. Een radio-edit die verloor omdat hij minder bekend
/// was dan de albumversie; een gast die "Culture Club" heette en daarom een clubmix werd; "Alive" van
/// Sia dat uit een Pearl Jam-radio viel omdat het zo heet als het zaad. Elk geval staat hier met de
/// naam waaronder het gevonden werd.
library;

import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/aanbevelingplan.dart' show SmaakProfiel;
import 'package:debridmusic/ai.dart';
import 'package:debridmusic/organize.dart' show TrackTags;
import 'package:debridmusic/radiobestand.dart';
import 'package:debridmusic/radiokeuze.dart';
import 'package:debridmusic/radiolijst.dart';
import 'package:debridmusic/radiostijl.dart';
import 'package:debridmusic/radiovoorraad.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

typedef _T = ({String artiest, String titel, int rang, int seconden});

bool klopt(String artiest, String titel, String pad) =>
    radioBestandKlopt(artiest: artiest, titel: titel, pad: pad);

void main() {
  group('"Radio hieruit" en het zaadnummer', () {
    test('DE KERN: een cover van het zaad blijft weg, een ander liedje met dezelfde naam niet', () {
      expect(
          isZaadlied('Tori Amos', 'Smells Like Teen Spirit',
              zaadArtiest: 'Nirvana', zaadTitel: 'Smells Like Teen Spirit'),
          isTrue,
          reason: 'vier woorden: dat is het liedje van Nirvana, door iemand anders gezongen');
      expect(isZaadlied('Sia', 'Alive', zaadArtiest: 'Pearl Jam', zaadTitel: 'Alive'), isFalse,
          reason: 'Alive van Sia is een ander liedje, en hoort in een Pearl Jam-radio');
      expect(
          isZaadlied('Stone Temple Pilots', 'Creep', zaadArtiest: 'Radiohead', zaadTitel: 'Creep'),
          isFalse,
          reason: 'een echte buur, die eerst verdween');
    });

    test('DE VAL: van de zaadartiest zelf blijft elke uitvoering weg', () {
      expect(isZaadlied('Radiohead', 'Creep (Acoustic)', zaadArtiest: 'Radiohead', zaadTitel: 'Creep'),
          isTrue);
      expect(
          isZaadlied('2 Fabiola feat. Loredana', 'Freak Out',
              zaadArtiest: '2 Fabiola', zaadTitel: "Freak Out ('97 Remix)"),
          isTrue);
      expect(isZaadlied('Pearl Jam', 'Black', zaadArtiest: 'Pearl Jam', zaadTitel: 'Alive'), isFalse);
    });

    test('DE KERN: je eigen uitvoering wordt het zaad — maar niet je remix ervan', () {
      final eigen = [
        (artiest: '2 Fabiola', titel: "Freak Out ('97 Remix)", seconden: 300),
        (artiest: '2 Fabiola', titel: 'Freak Out', seconden: 225),
      ];
      expect(eigenZaadIndex(eigen, '2 Fabiola', 'Freak Out', seconden: 224, speling: kRadioSpeling), 1);
      expect(eigenZaadIndex(eigen.sublist(0, 1), '2 Fabiola', 'Freak Out', speling: kRadioSpeling),
          isNull,
          reason: 'dan wordt het gehaald, en begint de radio niet met de remix');
      expect(eigenZaadIndex(eigen, 'Cappella', 'Freak Out', speling: kRadioSpeling), isNull);
    });
  });

  group('welke uitvoering het model bedoelde', () {
    test('DE KERN: een radio-edit wint, ook als hij minder dan half zo bekend is', () {
      final treffers = <_T>[
        (artiest: 'Culture Beat', titel: 'Mr. Vain', rang: 626305, seconden: 336),
        (artiest: 'Culture Beat', titel: 'Mr. Vain (Original Radio Edit)', rang: 200000, seconden: 256),
      ];
      expect(besteTreffer(treffers, 'Culture Beat', 'Mr. Vain'), 1,
          reason: 'bij de eerste controle koos de radio in 9 van de 25 nummers de albumversie');
    });

    test('DE VAL: maar een kale, obscure uitvoering wint niet van de soundtrack', () {
      final treffers = <_T>[
        (artiest: 'Bee Gees', titel: "Stayin' Alive", rang: 29823, seconden: 235),
        (
          artiest: 'Bee Gees',
          titel: "Stayin' Alive - From \"Saturday Night Fever\" Soundtrack",
          rang: 722791,
          seconden: 285
        ),
      ];
      expect(besteTreffer(treffers, 'Bee Gees', "Stayin' Alive"), 1);
      expect(besteTreffer(treffers.reversed.toList(), 'Bee Gees', "Stayin' Alive"), 0,
          reason: 'de volgorde van de treffers maakt niets uit');
    });

    test('DE KERN: een onbekende toevoeging wijkt voor een versie die bijna even bekend is', () {
      final treffers = <_T>[
        (artiest: 'Mr. President', titel: 'Coco Jamboo (Einstein Dr. Dj Konzept)', rang: 120000, seconden: 230),
        (artiest: 'Mr. President', titel: 'Coco Jamboo (Radio Edit)', rang: 100000, seconden: 220),
      ];
      expect(besteTreffer(treffers, 'Mr. President', 'Coco Jamboo'), 1);
      expect(besteTreffer(treffers.reversed.toList(), 'Mr. President', 'Coco Jamboo'), 0);
    });

    test('DE GRENS: maar vijf keer zo bekend is de versie die iedereen kent', () {
      final treffers = <_T>[
        (artiest: 'Mr. President', titel: 'Coco Jamboo (Einstein Dr. Dj Konzept)', rang: 500000, seconden: 230),
        (artiest: 'Mr. President', titel: 'Coco Jamboo (Radio Edit)', rang: 100000, seconden: 220),
      ];
      expect(besteTreffer(treffers, 'Mr. President', 'Coco Jamboo'), 0,
          reason: 'de toevoeging beslist alleen binnen een factor twee');
    });

    test('DE GRENS: een naspeler met dezelfde woorden is niet de band', () {
      final treffers = <_T>[
        (artiest: 'Smashing Pumpkins Tribute', titel: '1979', rang: 5000, seconden: 260),
      ];
      expect(besteTreffer(treffers, 'The Smashing Pumpkins', '1979'), isNull);
      expect(zelfdeArtiest('Dave Matthews', 'Dave Matthews Band'), isTrue,
          reason: '"band" maakt er geen naspeler van');
      expect(zelfdeArtiest('Hall & Oates', 'Daryl Hall & John Oates'), isTrue);
    });
  });

  group('wat een titel over de uitvoering zegt', () {
    test('DE KERN: een gast is geen versie', () {
      expect(uitvoeringVan('Song (feat. Culture Club)'), Uitvoering.origineel,
          reason: '"club" stond erin, en dat werd een clubmix');
      expect(uitvoeringVan('Song (feat. Oliver Heldens)'), Uitvoering.origineel,
          reason: '"o-live-r" was een live-opname');
      expect(uitvoeringVan('Song (with Ellie Goulding)'), Uitvoering.origineel);
      expect(uitvoeringVan('Song (with Culture Club)'), Uitvoering.origineel);
      expect(uitvoeringVan('Song (Oliver Twist Version)'), Uitvoering.origineel,
          reason: '"live" als losse tekst stond in elke Oliver');
    });

    test('DE VAL: een remix blijft een remix, ook achter een gast', () {
      expect(uitvoeringVan('Song (feat. X Remix)'), Uitvoering.bewerking);
      expect(uitvoeringVan('Song (with X Remix)'), Uitvoering.bewerking);
      expect(uitvoeringVan('Song (feat. X) [Y Remix]'), Uitvoering.bewerking);
      expect(uitvoeringVan('Song (Live at Wembley)'), Uitvoering.bewerking);
      expect(uitvoeringVan('Dance With Me (Club Mix)'), Uitvoering.bewerking);
    });

    test('DE KERN: een film, een heruitgave of een land is geen onbekende toevoeging', () {
      expect(vreemdeStaart("Stayin' Alive - From \"Saturday Night Fever\" Soundtrack"), isFalse);
      expect(vreemdeStaart('Song (Digitally Remastered)'), isFalse);
      expect(vreemdeStaart('Song (US Radio Edit)'), isFalse);
      expect(vreemdeStaart('Song (Deluxe Edition)'), isFalse);
      expect(vreemdeStaart('Song - Radioversion'), isFalse);
      expect(
          vreemdeStaart('Sweet Dreams (Are Made of This)', gevraagd: 'Sweet Dreams (Are Made of This)'),
          isFalse,
          reason: 'wat in de gevraagde titel staat, hoort bij de naam van het liedje');
    });

    test('DE VAL: per paar haakjes — een gast verbergt de naam erna niet', () {
      expect(vreemdeStaart('Song (feat. X) (Einstein Konzept)'), isTrue);
      expect(vreemdeStaart('Song (From "X" Soundtrack) (Einstein Konzept)'), isTrue);
      expect(vreemdeStaart('Song (feat. X)'), isFalse);
    });
  });

  group('de Deezer-lijst kiest net als het model', () {
    test('DE KERN: de radio-edit van singlelengte wint van de albumversie', () {
      final aanbod = [
        (artiest: 'Culture Beat', titel: 'Mr. Vain'),
        (artiest: 'Culture Beat', titel: 'Mr. Vain (Radio Edit)'),
      ];
      expect(kiesNummers(aanbod, seconden: [336, 256]), [1],
          reason: 'eerst won de kale titel van 5:36, vóór er naar de lengte gekeken werd');
      expect(kiesNummers(aanbod), [0], reason: 'zonder lengte blijft de gewone titel de voorkeur');
    });

    test('DE VAL: een duo onder twee schrijfwijzen is één liedje', () {
      final aanbod = [
        (artiest: '2 Fabiola feat. Loredana', titel: 'Freak Out'),
        (artiest: '2 Fabiola', titel: 'Freak Out (Radio Edit)'),
      ];
      expect(kiesNummers(aanbod).length, 1);
    });

    test('DE GRENS: AC/DC is één band, "A / B" twee', () {
      expect(artiestDelenTekst('AC/DC'), ['ac/dc']);
      expect(artiestSleutel('AC/DC'), 'acdc');
      expect(artiestDelenTekst('Tiësto / Oliver Heldens'), ['tiësto', 'oliver heldens']);
    });
  });

  group('grunge die Discogs ook metal noemt', () {
    test('DE KERN: een gemengde uitgave stemt voor geen van beide', () {
      expect(rockTak(['Grunge', 'Hard Rock', 'Heavy Metal']), 'gemengd',
          reason: 'zo beschrijft Discogs Alice in Chains — die viel uit een Nirvana-radio');
      expect(rockTak(['Grunge', 'Alternative Rock']), 'alternatief');
      expect(rockTak(['Hard Rock', 'Arena Rock']), 'klassiek');
      expect(rockTak(['Euro House']), isNull);
    });

    test('DE VAL: één zuivere uitgave tussen gemengde beslist niets', () {
      expect(meerderheidTak(['gemengd', 'gemengd', 'gemengd', 'klassiek']), isNull,
          reason: 'anders viel Alice in Chains er alsnog uit, alleen in een andere vorm');
      expect(meerderheidTak(['alternatief', 'alternatief', 'gemengd', null]), 'alternatief');
      expect(meerderheidTak(['alternatief', 'gemengd']), 'alternatief');
      // Gemeten op Discogs: Bon Jovi — Keep the Faith, 4 klassiek en 5 gemengd.
      expect(meerderheidTak([for (var i = 0; i < 4; i++) 'klassiek', for (var i = 0; i < 5; i++) 'gemengd']),
          'klassiek', reason: 'met "meer dan de helft" kwam Bon Jovi weer door een Nirvana-radio');
      // En Alice in Chains — Would?: 3 alternatief, 7 gemengd. Past overal, en nooit klassiek.
      expect(meerderheidTak([for (var i = 0; i < 3; i++) 'alternatief', for (var i = 0; i < 7; i++) 'gemengd']),
          isNull);
      expect(meerderheidTak(['klassiek', 'klassiek', 'alternatief']), 'klassiek');
    });

    test('DE VAL: Alice in Chains blijft in een Nirvana-radio, Bon Jovi niet', () async {
      final map = Directory.systemTemp.createTempSync('dm_eind_');
      addTearDown(() {
        try {
          map.deleteSync(recursive: true);
        } catch (_) {}
      });
      final b = Stijlboek(
        bestand: File('${map.path}${Platform.pathSeparator}radiostijl.json'),
        audioDbGenre: (_) async => 'Rock',
        discogsNummer: (a, t) async => switch (a) {
          'Alice in Chains' => [
              (jaar: 1992, genres: ['Rock'], stijlen: ['Grunge', 'Hard Rock', 'Heavy Metal']),
              (jaar: 1992, genres: ['Rock'], stijlen: ['Grunge', 'Hard Rock']),
            ],
          'Bon Jovi' => [(jaar: 1992, genres: ['Rock'], stijlen: ['Hard Rock', 'Arena Rock'])],
          _ => const <DiscogsUitgave>[],
        },
      );
      const zaad = (familie: Stijlfamilie.rock, jaar: 1991);
      expect((await b.keur('Alice in Chains', 'Would?', zaad, zaadTak: 'alternatief')).mag, isTrue);
      expect((await b.keur('Bon Jovi', 'Keep the Faith', zaad, zaadTak: 'alternatief')).mag, isFalse);
    });

    test('DE GRENS: een geheugen van oudere regels wordt opnieuw opgezocht', () async {
      final map = Directory.systemTemp.createTempSync('dm_eind_');
      addTearDown(() {
        try {
          map.deleteSync(recursive: true);
        } catch (_) {}
      });
      final bestand = File('${map.path}${Platform.pathSeparator}radiostijl.json');
      // Zo zag het geheugen eruit vóór [kStijlboekVersie]: geen versie, en een verkeerde tak.
      bestand.writeAsStringSync(
          '{"n:aliceinchains|would": {"f": ["rock"], "j": 1992, "t": "klassiek"}, "a:aliceinchains": "rock"}');
      var gevraagd = 0;
      final audioDb = <String>[];
      final b = Stijlboek(
        bestand: bestand,
        audioDbGenre: (a) async {
          audioDb.add(a);
          return 'Rock';
        },
        discogsNummer: (a, t) async {
          gevraagd++;
          return [(jaar: 1992, genres: ['Rock'], stijlen: ['Grunge', 'Hard Rock', 'Heavy Metal'])];
        },
      );
      await b.nummer('Alice in Chains', 'Would?');
      expect(gevraagd, 1, reason: 'anders valt een nummer nooit meer onder de nieuwe regels');
      expect(await b.tak('Alice in Chains', 'Would?'), isNull);
      expect(await b.artiest('Alice in Chains'), Stijlfamilie.rock);
      expect(audioDb, isEmpty,
          reason: 'het genre van een artiest is nog waar — en elke vraag kost drie seconden');
    });

    test('DE KERN: een half antwoord van Discogs wordt niet bewaard', () {
      final eerst = [(jaar: 2018, genres: ['Rock'], stijlen: ['Grunge'])];
      expect(samenUitgaven(eerst, null), isNull,
          reason: 'Mudhoney: alleen het live-album van 2018, en dan voorgoed 2018');
      expect(samenUitgaven(eerst, [(jaar: 1988, genres: ['Rock'], stijlen: ['Grunge'])])?.length, 2);
    });
  });

  group('wat de map over een Soulseek-bestand zegt', () {
    test('DE KERN: Live Through This is een studioplaat', () {
      expect(klopt('Hole', 'Doll Parts', r'Hole\Live Through This (1994)\04 - Doll Parts.flac'), isTrue);
      expect(klopt('Wings', 'Live and Let Die', r'Wings\Live and Let Die (Single)\01 - Live and Let Die.flac'),
          isTrue);
    });

    test('DE VAL: een live-plaat blijft een live-plaat', () {
      expect(klopt('Hole', 'Doll Parts', r'Hole\Live At Reading 1994\04 - Doll Parts.flac'), isFalse);
      expect(klopt('Hole', 'Doll Parts', r'Hole - Live\04 - Doll Parts.flac'), isFalse);
      expect(klopt('Hole', 'Doll Parts', r'Hole\Doll Parts (Live)\01 - Doll Parts.flac'), isFalse);
      expect(klopt('Scooter', 'Hyper Hyper', r'Scooter\Encore - Live And Direct (2002)\05 - Hyper Hyper.flac'),
          isFalse);
    });

    test('DE KERN: unplugged, akoestisch en sessies zijn geen origineel', () {
      expect(
          klopt('Nirvana', 'About a Girl', r'Nirvana\MTV Unplugged in New York\01 - About a Girl.flac'),
          isFalse);
      expect(klopt('Nirvana', 'Lithium', r'Nirvana\BBC Sessions\03 - Lithium.flac'), isFalse);
      expect(klopt('Nirvana', 'Lithium', r'Nirvana\Nevermind (1991)\05 - Lithium.flac'), isTrue);
    });

    test('DE VAL: een woord van de titel in de map is de titel, geen verklikker', () {
      expect(klopt('Tenacious D', 'Tribute', r'Tenacious D\Tribute (Single)\01 - Tribute.flac'), isTrue,
          reason: '"tribute" in de map is hier de naam van het liedje');
      expect(klopt('Tenacious D', 'Wonderboy', r'Tenacious D\Tribute Hits\01 - Wonderboy.flac'), isFalse);
      expect(
          klopt('Bruce Springsteen', 'Cover Me',
              r'Bruce Springsteen\Born in the U.S.A. (1984)\02 - Cover Me.flac'),
          isTrue,
          reason: 'de coverwacht las de titel achter de streep als aankondiging');
      expect(
          klopt('Haddaway', 'What Is Love', r'Haddaway Hits\What Is Love (Karaoke Version).mp3'),
          isFalse);
    });

    test('DE KERN: een duo onder zijn korte naam', () {
      expect(
          klopt('Daryl Hall & John Oates', 'Maneater',
              r'Hall & Oates - Greatest Hits\01 - Maneater.flac'),
          isTrue);
      expect(klopt('Daryl Hall & John Oates', 'Maneater', r'Hall Of Fame\01 - Maneater.flac'), isFalse,
          reason: 'één woord van de naam is niet de naam');
    });
  });

  // ── De tweede beoordeling van 26-09-2026 ──────────────────────────────────────────────────────

  group('live-platen die langs het lijstje glipten', () {
    test('DE KERN: "Live" + een zelfstandig naamwoord is een live-plaat', () {
      expect(klopt('Iron Maiden', 'The Trooper', r'Iron Maiden\1985 - Live After Death\CD1\03 - The Trooper.flac'),
          isFalse);
      expect(klopt('AC/DC', 'Thunderstruck', r'AC-DC - Live (1992)\01 - Thunderstruck.flac'), isFalse,
          reason: '"(1992)" versloeg eerst elke vorm');
      expect(klopt('Queen', 'Bohemian Rhapsody', r'Queen\Live Killers (1979)\CD2\05 - Bohemian Rhapsody.flac'),
          isFalse);
    });

    test('DE VAL: "live" in de titel schakelt de toets niet meer uit', () {
      expect(
          klopt('Oasis', 'Live Forever', r'Oasis\Familiar To Millions (Live)\CD1\03 - Live Forever.flac'),
          isFalse);
      expect(klopt('Oasis', 'Live Forever', r"Oasis\Definitely Maybe (1994)\03 - Live Forever.flac"), isTrue);
      expect(klopt('Opus', 'Live Is Life', r'Opus\Live Is Life (Single)\01 - Live Is Life.flac'), isTrue,
          reason: 'de titel in de map is de titel, geen live-plaat');
    });

    test('DE VAL: en de naam van de band Live ook niet', () {
      expect(klopt('Live', 'Lightning Crashes', r'Live\Live At The Paradiso\05 - Lightning Crashes.flac'),
          isFalse);
      expect(klopt('Live', 'Lightning Crashes', r'Live\Throwing Copper (1994)\05 - Lightning Crashes.flac'),
          isTrue);
      expect(klopt('Live', 'Lightning Crashes', r'Live - Throwing Copper (1994)\05 - Lightning Crashes.flac'),
          isTrue);
    });
  });

  group('één keuze voor de Deezer-lijst en de lijst van het model', () {
    const stayin = [
      (artiest: 'Bee Gees', titel: "Stayin' Alive", rang: 29823, seconden: 235),
      (artiest: 'Bee Gees', titel: "Stayin' Alive - From \"Saturday Night Fever\" Soundtrack", rang: 722791, seconden: 285),
    ];

    test('DE KERN: met de bekendheid erbij kiest Deezer de soundtrack, net als het model', () {
      final aanbod = [for (final t in stayin) (artiest: t.artiest, titel: t.titel)];
      final deezer = kiesNummers(aanbod,
          seconden: [for (final t in stayin) t.seconden], rang: [for (final t in stayin) t.rang]);
      expect(deezer, [besteTreffer(stayin, 'Bee Gees', "Stayin' Alive")],
          reason: 'eerst kreeg Deezer de obscure live-opname en het model de soundtrack');
      expect(deezer, [1]);
    });

    test('DE GRENS: een bewerking alleen als er niets anders is', () {
      final aanbod = [
        (artiest: 'Haddaway', titel: 'What Is Love (Club Mix)'),
        (artiest: 'Haddaway', titel: 'What Is Love (7" Mix)'),
      ];
      expect(kiesNummers(aanbod, rang: [900000, 10], seconden: [400, 250]), [1],
          reason: 'de clubmix is bekender, maar er is een gewone versie');
    });
  });

  group('naspelers en nieuwe opnames', () {
    test('DE KERN: een show, een "of" of een erfenis is niet de band', () {
      expect(zelfdeArtiest('The Australian Pink Floyd Show', 'Pink Floyd'), isFalse);
      expect(zelfdeArtiest('Rumours of Fleetwood Mac', 'Fleetwood Mac'), isFalse);
      expect(zelfdeArtiest('Dire Straits Legacy', 'Dire Straits'), isFalse);
      expect(zelfdeArtiest('Brit Pink Floyd Collective', 'Pink Floyd'), isFalse,
          reason: 'twee woorden erbij in één deel is een andere groep, ook zonder verklikwoord');
    });

    test('DE VAL: maar een voornaam, "and" of een lidwoord wel', () {
      expect(zelfdeArtiest('Hall & Oates', 'Daryl Hall and John Oates'), isTrue);
      expect(zelfdeArtiest('Florence + The Machine', 'Florence and the Machine'), isTrue);
      expect(zelfdeArtiest('Dave Matthews', 'Dave Matthews Band'), isTrue);
    });

    test('DE KERN: een orkest is geen gast maar een nieuwe opname', () {
      expect(uitvoeringVan('Song (with The Royal Philharmonic Orchestra)'), Uitvoering.bewerking);
      expect(uitvoeringVan('Song (feat. London Symphony Orchestra)'), Uitvoering.bewerking);
      expect(uitvoeringVan('Song (with Strings)'), Uitvoering.bewerking);
      expect(uitvoeringVan('Song (with Ellie Goulding)'), Uitvoering.origineel);
    });

    test('DE GRENS: een apostrof maakt geen woord', () {
      expect(isZaadlied('Seal', "Don't Cry", zaadArtiest: "Guns N' Roses", zaadTitel: "Don't Cry"), isFalse,
          reason: 'twee woorden, een ander liedje');
    });
  });

  group('het zaad zonder tag', () {
    test('DE KERN: zonder tag en zonder Discogs het jaar van het Deezer-album', () async {
      final map = Directory.systemTemp.createTempSync('dm_eind_');
      addTearDown(() {
        try {
          map.deleteSync(recursive: true);
        } catch (_) {}
      });
      final b = Stijlboek(
        bestand: File('${map.path}${Platform.pathSeparator}radiostijl.json'),
        audioDbGenre: (_) async => 'Dance',
        discogsNummer: (a, t) async => null,
        deezerJaar: (a, t) async => 1996,
      );
      final z = await b.zaad('2 Fabiola', 'Freak Out');
      expect(z.jaar, 1996, reason: 'anders was er bij een radio vanaf een aanbeveling geen tijdvak');
    });
  });

  // ── De derde beoordeling van 26-09-2026 ───────────────────────────────────────────────────────

  group('studioplaten met "live" erin, en live-platen zonder', () {
    test('DE KERN: "Long Live …" en een studiotitel zijn geen live-plaat', () {
      expect(klopt('Rainbow', 'Kill the King', r"Rainbow\Long Live Rock 'n' Roll (1978)\02 - Kill the King.flac"),
          isTrue);
      expect(klopt('Emeli Sandé', 'Hurts', r'Emeli Sandé\Long Live the Angels (2016)\01 - Hurts.flac'), isTrue);
      expect(klopt('Metric', 'Collect Call', r'Metric\Live It Out (2005)\04 - Collect Call.flac'), isTrue);
      expect(klopt('Wang Chung', 'Wait', r'Wang Chung\To Live and Die in L.A. (1985)\03 - Wait.flac'), isTrue);
    });

    test('DE VAL: een concert en "Alive!" zijn wel live', () {
      expect(
          klopt('Simon & Garfunkel', 'Mrs. Robinson',
              r'Simon & Garfunkel\The Concert in Central Park\03 - Mrs. Robinson.flac'),
          isFalse);
      expect(klopt('KISS', 'Strutter', r'KISS\Alive! (1975)\02 - Strutter.flac'), isFalse);
    });

    test('DE KERN: de band Live met elk soort streepje, een jaartal of "The"', () {
      expect(klopt('Live', 'Lightning Crashes', 'Live – Throwing Copper\\05 - Lightning Crashes.flac'), isTrue);
      expect(klopt('Live', 'Lightning Crashes', r'Live-Throwing Copper\05 - Lightning Crashes.flac'), isTrue);
      expect(klopt('Live', 'Lightning Crashes', r'(1994) Live - Throwing Copper\05 - Lightning Crashes.flac'),
          isTrue);
      expect(
          klopt('The 2 Live Crew', 'Me So Horny', r'2 Live Crew - As Nasty As They Wanna Be\05 - Me So Horny.flac'),
          isTrue);
      expect(klopt('The 2 Live Crew', 'Me So Horny', r'2 Live Crew\Live in Concert\05 - Me So Horny.flac'),
          isFalse);
      expect(klopt('The 2 Live Crew', 'Me So Horny', r'Best Of 2 Live Crew\05 - Me So Horny.flac'), isTrue,
          reason: 'een naam van meer woorden kan midden in een map niets anders betekenen');
    });

    test('DE GRENS: de titel één keer, niet elk woord dat erop lijkt', () {
      expect(klopt('Tenacious D', 'Tribute', r'Diversen\Tribute - Tenacious D Tribute.mp3'), isFalse);
    });
  });

  group('de rocktak van een plaat die er niets over zegt', () {
    test('DE KERN: Prog Rock telt mee, als stem voor geen van beide', () {
      final floyd = [
        for (var i = 0; i < 8; i++) (jaar: 1979, genres: ['Rock'], stijlen: ['Prog Rock']),
        for (var i = 0; i < 2; i++) (jaar: 1979, genres: ['Rock'], stijlen: ['Prog Rock', 'Art Rock']),
      ];
      expect(meerderheidTak([for (final u in floyd) takVanUitgave(u)]), isNull,
          reason: 'twee van twee was alternatief, en dan viel Pink Floyd uit een Led Zeppelin-radio');
      expect(takVanUitgave((jaar: 1994, genres: ['Electronic'], stijlen: ['Euro House'])), isNull);
      expect(takVanUitgave((jaar: 1979, genres: ['Rock'], stijlen: ['Art Rock'])), 'gemengd',
          reason: 'Art Rock is Pink Floyd net zo goed als Radiohead');
      final twee = [
        for (var i = 0; i < 8; i++) (jaar: 1979, genres: ['Rock'], stijlen: ['Prog Rock']),
        for (var i = 0; i < 2; i++) (jaar: 1979, genres: ['Rock'], stijlen: ['Alternative Rock']),
      ];
      expect(meerderheidTak([for (final u in twee) takVanUitgave(u)]), isNull,
          reason: 'twee van tien is minder dan een derde, ook al zeggen de andere acht niets');
      expect(takVanUitgave((jaar: 1994, genres: ['Rock'], stijlen: ['Grunge'])), 'alternatief');
    });
  });

  group('duo\'s, bands en naspelers, derde ronde', () {
    test('DE KERN: "and" is geen woord van de naam', () {
      expect(zelfdeArtiest('Hall and Oates', 'Daryl Hall & John Oates'), isTrue);
      expect(klopt('Daryl Hall & John Oates', 'Maneater', r'Hall and Oates - Greatest Hits\Maneater.flac'),
          isTrue);
      expect(zelfdeArtiest('Nick Cave', 'Nick Cave and the Bad Seeds'), isTrue,
          reason: 'een deel dat niets deelt telt niet mee');
    });

    test('DE VAL: één woord áchter de naam is een andere groep', () {
      expect(zelfdeArtiest('Bon Jovi Forever', 'Bon Jovi'), isFalse);
      expect(zelfdeArtiest('The Pink Floyd Project', 'Pink Floyd'), isFalse);
      expect(zelfdeArtiest('Fleetwood Mac UK', 'Fleetwood Mac'), isFalse);
      expect(zelfdeArtiest('Dave Matthews Band', 'Dave Matthews'), isTrue, reason: 'behalve "band"');
      expect(zelfdeArtiest('Daryl Hall & John Oates', 'Hall & Oates'), isTrue, reason: 'een voornaam vooraan');
    });

    test('DE KERN: een filmnaam maakt geen clubmix', () {
      expect(uitvoeringVan("Don't You (Forget About Me) - From \"The Breakfast Club\" Soundtrack"),
          Uitvoering.origineel);
    });
  });

  // ── De vierde beoordeling van 26-09-2026 ──────────────────────────────────────────────────────

  group('"and the" en echte bands met een naspelerwoord', () {
    test('DE KERN: "Prince and The Revolution" is Prince', () {
      expect(zelfdeArtiest('Prince and The Revolution', 'Prince'), isTrue);
      expect(artiestSleutel('Prince and The Revolution'), artiestSleutel('Prince'),
          reason: 'anders telde het niet mee voor het plafond van de zaadartiest');
      expect(
          isZaadlied('Prince', 'Purple Rain', zaadArtiest: 'Prince and The Revolution', zaadTitel: 'Purple Rain'),
          isTrue,
          reason: 'anders speelde het zaad een tweede keer');
      expect(zelfdeArtiest('Bob Marley and the Wailers', 'Bob Marley'), isTrue);
    });

    test('DE VAL: The Jimi Hendrix Experience is Jimi Hendrix, geen naspeler', () {
      expect(zelfdeArtiest('The Jimi Hendrix Experience', 'Jimi Hendrix'), isTrue);
      expect(zelfdeArtiest('The Nirvana Experience', 'Nirvana Tribute'), isFalse);
    });

    test('DE GRENS: een land vooraan is geen voornaam', () {
      expect(zelfdeArtiest('Australian Pink Floyd', 'Pink Floyd'), isFalse);
      expect(zelfdeArtiest('UK Foo Fighters', 'Foo Fighters'), isFalse);
      expect(zelfdeArtiest('Daryl Hall & John Oates', 'Hall & Oates'), isTrue);
    });
  });

  group('de band Live en "Alive"-platen, vierde ronde', () {
    test('DE KERN: "(Band)" achter de naam en "Best Of Live" zijn de naam', () {
      expect(klopt('Live', 'Lightning Crashes', r'Live - Awake - The Best Of Live (2004)\02 - Lightning Crashes.flac'),
          isTrue);
      expect(klopt('Live', 'Lightning Crashes', r'Live (Band)\Throwing Copper\05 - Lightning Crashes.flac'), isTrue);
      expect(klopt('Live', 'Lightning Crashes', r'Live [US]\Throwing Copper\05 - Lightning Crashes.flac'), isTrue);
    });

    test('DE VAL: "Alive II" en "Alive 2007" zijn live', () {
      expect(klopt('KISS', 'Detroit Rock City', r'KISS\1977 - Alive II\01 - Detroit Rock City.flac'), isFalse);
      expect(klopt('Daft Punk', 'Around the World', r'Daft Punk\2007 - Alive 2007\05 - Around the World.flac'),
          isFalse);
      expect(klopt('Pearl Jam', 'Alive', r'Pearl Jam\Alive (Single)\01 - Alive.flac'), isTrue);
    });
  });

  // ── Live gevolgd op het scherm, 26-09-2026 17:15 — radio vanaf Freak Out ─────────────────────

  group('de zaadartiest klontert niet aan het begin', () {
    // Zo stond de radio bij de start: het zaad, twee eigen nummers van 2 Fabiola die al klaar zijn,
    // en drie plekken die nog gehaald moeten worden.
    final standen = [
      Haalstand.klaar, Haalstand.klaar, Haalstand.wacht, Haalstand.klaar, Haalstand.wacht, Haalstand.wacht,
    ];
    final artiesten = ['2 Fabiola', '2 Fabiola', 'Cappella', '2 Fabiola', 'Haddaway', 'Corona'];
    final seconden = [215, 200, 220, 210, 240, 260];

    test('DE KERN: met het zaad van 3:35 in de rij komt er geen tweede 2 Fabiola achter', () {
      final b = voorraadPlan(standen,
          artiesten: artiesten, vooruitNu: 0, restSeconden: 0, seconden: seconden);
      expect(b.inRij, [0],
          reason: 'eerst: Freak Out, Flashback, Let The Music Play — vier keer 2 Fabiola in de eerste tien');
      expect(b.starten, [2, 4, 5]);
    });

    test('DE VAL: onder de minuut liever dezelfde artiest dan stilte', () {
      final b = voorraadPlan([Haalstand.klaar, Haalstand.wacht],
          artiesten: ['2 Fabiola', 'Cappella'], staart: ['2 Fabiola'], vooruitNu: 0, restSeconden: 40,
          seconden: [200, 220]);
      expect(b.inRij, [0]);
    });

    test('DE GRENS: een net geland nummer van dezelfde artiest wacht ook', () {
      final b = voorraadPlan([Haalstand.geland],
          artiesten: ['2 Fabiola'], staart: ['2 Fabiola'], vooruitNu: 0, restSeconden: 190, seconden: [210]);
      expect(b.inRij, isEmpty, reason: '"I\'m On Fire" landde en stond meteen achter het zaad');
      final zonderTijd = voorraadPlan([Haalstand.geland], artiesten: ['2 Fabiola'], staart: ['2 Fabiola'], vooruitNu: 0);
      expect(zonderTijd.inRij, [0], reason: 'zonder tijd telt hij nummers, zoals voorheen');
    });

    test('DE KERN: de zaadartiest hoogstens één op de tien IN DE RIJ', () {
      // 3.9.417, 17:48: 2 Fabiola op plek 1, 6, 10 en 14 — het plan hield zich aan één op de tien, de
      // rij niet. Hier staat het zaad vijf plekken terug.
      const staart = ['2 Fabiola', 'Cappella', 'Haddaway', 'Dune', 'Snap!'];
      final b = voorraadPlan([Haalstand.klaar, Haalstand.klaar],
          artiesten: ['2 Fabiola', 'Corona'], staart: staart, vooruitNu: 2, restSeconden: 300,
          seconden: [200, 240], zaad: '2 Fabiola');
      expect(b.inRij, [1], reason: 'Corona wel, 2 Fabiola pas na tien plekken');
      final gewoon = voorraadPlan([Haalstand.klaar, Haalstand.klaar],
          artiesten: ['2 Fabiola', 'Corona'], staart: staart, vooruitNu: 2, restSeconden: 300,
          seconden: [200, 240]);
      expect(gewoon.inRij, [0, 1], reason: 'voor een gewone artiest is vier plekken genoeg');
      final krap = voorraadPlan([Haalstand.klaar],
          artiesten: ['2 Fabiola'], staart: staart, vooruitNu: 0, restSeconden: 30, seconden: [200],
          zaad: '2 Fabiola');
      expect(krap.inRij, [0], reason: 'onder de minuut liever 2 Fabiola dan stilte');
    });
  });

  group('een bestand dat de app niet kan beschrijven', () {
    TrackTags tags(String artiest, String titel) =>
        TrackTags(title: titel, artist: artiest, album: '', trackNo: 0);

    test('DE KERN: een AIFF zonder tags is onbruikbaar, een FLAC niet', () {
      expect(radioZonderTags(null, r'D:\x\01 Haddaway - What Is Love.aiff'), isTrue,
          reason: 'die stond als "Onbekende artiest" in de rij');
      expect(radioZonderTags(null, r'D:\x\01 Haddaway - What Is Love.flac'), isFalse,
          reason: 'die tags schrijft de radio er zelf in');
      expect(radioZonderTags(tags('Haddaway', 'What Is Love'), r'D:\x\What Is Love.aiff'), isFalse);
    });

    test('DE GRENS: alleen FLAC en MP3 zijn te taggen', () {
      expect(radioTagsSchrijfbaar('a.FLAC'), isTrue);
      expect(radioTagsSchrijfbaar('a.mp3'), isTrue);
      expect(radioTagsSchrijfbaar('a.wav'), isFalse);
      expect(radioTagsSchrijfbaar('a.aiff'), isFalse);
    });
  });

  group('het model dat een keer niets geeft', () {
    http.Response antwoord(List<(String, String)> nummers, String stop) => http.Response(
        jsonEncode({
          'content': [
            {
              'type': 'text',
              'text': jsonEncode({
                'nummers': [
                  for (final (a, t) in nummers) {'artiest': a, 'titel': t, 'jaar': 1994, 'bekend': true}
                ]
              })
            }
          ],
          'stop_reason': stop,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'});
    final twintig = [for (var i = 0; i < 20; i++) ('Artiest $i', 'Nummer $i')];

    // Een verzonnen sleutel: het verzoek gaat naar de nep-client en nergens anders heen.
    AiService model(http.Response Function(int vraag) wat) {
      var vraag = 0;
      return AiService(() => 'sk-ant-toets', client: MockClient((_) async => wat(++vraag)));
    }

    test('DE KERN: één "placeholder" is geen lijst — de radio vraagt het één keer opnieuw', () async {
      var vragen = 0;
      final ai = model((v) {
        vragen = v;
        return v == 1 ? antwoord([('技', 'placeholder')], 'max_tokens') : antwoord(twintig, 'end_turn');
      });
      final lijst = await ai.maakRadiolijst(artiest: '2 Fabiola', titel: 'Freak Out', profiel: const SmaakProfiel());
      expect(vragen, 2, reason: 'op 26-09-2026 deed het model zo niet mee, en kwam alles van Deezer');
      expect(lijst.length, 20);
      expect(ai.laatsteStop, 'end_turn');
    });

    test('DE VAL: een goede lijst wordt niet nog eens gevraagd', () async {
      var vragen = 0;
      final ai = model((v) {
        vragen = v;
        return antwoord(twintig, 'end_turn');
      });
      await ai.maakRadiolijst(artiest: '2 Fabiola', profiel: const SmaakProfiel());
      expect(vragen, 1, reason: 'elke vraag kost geld en twintig seconden');
    });

    test('DE GRENS: een invulplek is geen nummer', () {
      final uit = leesNummers({
        'nummers': [
          {'artiest': 'Placeholder', 'titel': 'Iets'},
          {'artiest': 'Snap!', 'titel': 'placeholder'},
          {'artiest': 'Snap!', 'titel': 'The Power'},
        ]
      });
      expect([for (final n in uit) n.titel], ['The Power']);
    });

    test('DE KERN: rommel vóór de naam en onzichtbare tekens gaan eraf', () {
      final uit = leesNummers({
        'nummers': [
          {'artiest': '技​ - Fun Factory', 'titel': 'Celebration'},
          {'artiest': 'Би-2', 'titel': 'Полковнику никто не пишет'},
          {'artiest': '2 Unlimited', 'titel': 'No​ Limit'},
          {'artiest': 'Snap​!', 'titel': 'The Power'},
        ]
      });
      expect([for (final n in uit) n.artiest], ['Fun Factory', 'Би-2', '2 Unlimited', 'Snap!'],
          reason: '18:21 op 26-09-2026: "技​ - Fun Factory" — en dan vond Deezer "Celebration" niet');
      expect(uit[2].titel, 'No Limit');
    });
  });
}
