/// Wat de eindbeoordeling van de radio op 26-09-2026 vond, en wat er sindsdien vastligt.
///
/// De radio kiest uit drie bronnen — Deezer, het taalmodel, Discogs en TheAudioDB als keuring — en
/// een laatste ronde langs alles vond negen plekken waar een regel die voor één voorbeeld gemaakt
/// was, een ander voorbeeld stil verkeerd deed. Een radio-edit die verloor omdat hij minder bekend
/// was dan de albumversie; een gast die "Culture Club" heette en daarom een clubmix werd; "Alive" van
/// Sia dat uit een Pearl Jam-radio viel omdat het zo heet als het zaad. Elk geval staat hier met de
/// naam waaronder het gevonden werd.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/aanbevelingplan.dart' show SmaakProfiel;
import 'package:debridmusic/deezerbaan.dart';
import 'package:debridmusic/ai.dart';
import 'package:debridmusic/organize.dart' show TrackTags;
import 'package:debridmusic/radiobestand.dart';
import 'package:debridmusic/radiokeuze.dart';
import 'package:debridmusic/radiolijst.dart';
import 'package:debridmusic/radiostijl.dart';
import 'package:debridmusic/radiovoorraad.dart';
import 'package:debridmusic/recommend.dart';
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

  // ── "De radio moet altijd kijken of het nummer al in men bibliotheek staat" (27-09-2026) ──────

  group('heb je dit al — op het liedje, niet op de titel', () {
    test('DE KERN: de drie liedjes die de radio op 26-09 opnieuw haalde', () {
      expect(eigenSleutel('Haddaway', 'What Is Love (Single Version)'),
          eigenSleutel('Haddaway', 'What Is Love (7” Mix)'),
          reason: 'drie keer gehaald: 17:17, 18:24 en 18:52');
      expect(eigenSleutel('T-Spoon', 'Take Me 2 The Limit [Radio Mix]'),
          eigenSleutel('T-Spoon', 'Take Me to the Limit'),
          reason: '"2" is "to" — om 11:51 en om 17:49 gehaald');
      expect(eigenSleutel('Cappella', 'U Got 2 Let The Music'),
          eigenSleutel('Cappella', 'U Got 2 Let The Music (Brescia Edit)'));
    });

    test('DE VAL: schrijfwijzen van hetzelfde woord, maar alleen hele woorden', () {
      expect(basisTitel("Rock 'n' Roll"), basisTitel('Rock & Roll'));
      expect(basisTitel('Rock and Roll'), basisTitel('Rock & Roll'));
      expect(basisTitel('U Got 2 Let The Music'), basisTitel('You Got to Let the Music'));
      expect(basisTitel('U-Turn'), isNot(basisTitel('You Turn')));
      expect(eigenSleutel('2 Unlimited', 'No Limit'), isNot(eigenSleutel('2 Unlimited', 'Tribal Dance')));
    });

    test('DE KERN: je eigen origineel wint van een benoemde remix-edit', () {
      expect(
          eigenPastOpPlek(
              plekTitel: 'No Limit (Big Dawg Radio Edit)',
              plekSeconden: 175,
              eigenTitel: 'No Limit',
              eigenSeconden: 227,
              speling: kRadioSpeling),
          isTrue,
          reason: 'je had het origineel van 3:47, en de radio haalde de Big Dawg-edit erbij');
      expect(
          eigenPastOpPlek(
              plekTitel: "Freak Out ('97 Remix)",
              plekSeconden: 215,
              eigenTitel: 'Freak Out',
              eigenSeconden: 230,
              speling: kRadioSpeling),
          isTrue);
    });

    test('DE GRENS: maar een plek zonder naam let op de lengte — Move On Baby', () {
      expect(
          eigenPastOpPlek(
              plekTitel: 'Move On Baby',
              plekSeconden: 220,
              eigenTitel: 'Move On Baby',
              eigenSeconden: 291,
              speling: kRadioSpeling),
          isFalse,
          reason: 'Saber: "move on baby is al niet goed, niet original" — dat was de albumversie');
      expect(
          eigenPastOpPlek(
              plekTitel: 'What Is Love (7” Mix)',
              plekSeconden: 207,
              eigenTitel: 'What Is Love (Single Version)',
              eigenSeconden: 210,
              speling: kRadioSpeling),
          isTrue);
      expect(
          eigenPastOpPlek(
              plekTitel: 'Freak Out',
              plekSeconden: 230,
              eigenTitel: "Freak Out ('97 Remix)",
              eigenSeconden: 215,
              speling: kRadioSpeling),
          isFalse,
          reason: 'een remix die je hebt is geen origineel dat gevraagd werd');
      expect(
          eigenPastOpPlek(
              plekTitel: 'No Limit (Big Dawg Radio Edit)',
              plekSeconden: 175,
              eigenTitel: 'No Limit (Automatic Radio Edit)',
              eigenSeconden: 240,
              speling: kRadioSpeling),
          isFalse,
          reason: 'twee benoemde varianten zijn niet vanzelf dezelfde');
    });
  });

  // ── Radio vanaf Sade "Cherish the Day", 27-09-2026 ────────────────────────────────────────────

  group('soul en jazz: een ruimer tijdvak, en de buren', () {
    const sade = (familie: Stijlfamilie.jazz, jaar: 1992);
    const freakOut = (familie: Stijlfamilie.dans, jaar: 1997);

    test('DE KERN: Marvin Gaye (1982) en Amy Winehouse (2006) horen bij Sade', () {
      expect(keurStijl(sade, (families: {Stijlfamilie.popsoul}, jaar: 1982)).mag, isTrue,
          reason: 'met acht jaar speling viel "Sexual Healing" eruit');
      expect(keurStijl(sade, (families: {Stijlfamilie.popsoul}, jaar: 2006)).mag, isTrue);
      expect(keurStijl(sade, (families: {Stijlfamilie.popsoul}, jaar: 1971)).mag, isFalse,
          reason: 'ruimer is niet eindeloos');
    });

    test('DE VAL: eurodance houdt zijn scherpe tijdvak en zijn eigen familie', () {
      expect(keurStijl(freakOut, (families: {Stijlfamilie.dans}, jaar: 1985)).mag, isFalse);
      expect(keurStijl(freakOut, (families: {Stijlfamilie.popsoul}, jaar: 1998)).mag, isFalse,
          reason: 'Britney hoort niet in een eurodanceradio — dat was gemeten goed');
    });

    test('DE GRENS: welke familie welke buren heeft', () {
      expect(tijdvakSpeling(Stijlfamilie.jazz), 20);
      expect(tijdvakSpeling(Stijlfamilie.popsoul), 12);
      expect(tijdvakSpeling(Stijlfamilie.dans), kTijdvakSpeling);
      expect(tijdvakSpeling(Stijlfamilie.rock), kTijdvakSpeling);
      expect(familiePast(Stijlfamilie.jazz, {Stijlfamilie.popsoul}), isTrue);
      expect(familiePast(Stijlfamilie.dans, {Stijlfamilie.popsoul}), isFalse);
      expect(sfeerBeslistFamilie(Stijlfamilie.jazz), isTrue);
      expect(sfeerBeslistFamilie(Stijlfamilie.popsoul), isTrue);
      expect(sfeerBeslistFamilie(Stijlfamilie.dans), isFalse);
      expect(sfeerBeslistFamilie(Stijlfamilie.rock), isFalse);
    });

    test('DE KERN: is de sfeer goed, dan telt bij soul en jazz alleen het tijdvak', () async {
      final map = Directory.systemTemp.createTempSync('dm_sade_');
      addTearDown(() {
        try {
          map.deleteSync(recursive: true);
        } catch (_) {}
      });
      final b = Stijlboek(
        bestand: File('${map.path}${Platform.pathSeparator}radiostijl.json'),
        audioDbGenre: (_) async => 'Rock',
        discogsNummer: (a, t) async => switch (a) {
          'Sting' => [(jaar: 1993, genres: ['Rock'], stijlen: ['Pop Rock'])],
          _ => [(jaar: 1971, genres: ['Funk / Soul'], stijlen: ['Soul'])],
        },
      );
      expect((await b.keur('Sting', 'Fields of Gold', sade)).mag, isFalse,
          reason: 'zonder sfeeroordeel beslist de familie, zoals voorheen');
      expect((await b.keur('Sting', 'Fields of Gold', sade, familieTelt: false)).mag, isTrue,
          reason: 'het model hoorde dat het bij Sade past; Discogs noemt het rock');
      expect((await b.keur('Donny Hathaway', 'A Song for You', sade, familieTelt: false)).mag, isFalse,
          reason: 'het tijdvak blijft gelden');
    });
  });

  group('de sfeervraag aan het model', () {
    const kandidaten = [
      (artiest: 'Anita Baker', titel: 'Sweet Love'),
      (artiest: 'Michael Jackson', titel: 'Smooth Criminal'),
      (artiest: 'Toni Braxton', titel: 'Another Sad Love Song'),
    ];

    test('DE KERN: de vraag noemt het zaad en elk nummer met een nummer', () {
      final v = sfeerPrompt(
          artiest: 'Sade', titel: 'Cherish the Day', jaar: 1992, stijlen: ['Soul-Jazz'], kandidaten: kandidaten);
      expect(v, contains('Sade - Cherish the Day (uit 1992, stijl Soul-Jazz)'));
      expect(v, contains('2. Michael Jackson - Smooth Criminal'));
      expect(v, contains('tempo'));
    });

    test('DE VAL: alleen nummers die in de lijst kunnen staan, vanaf nul', () {
      expect(leesSfeer({'weg': [2, 9, 0, '3']}, kandidaten.length), {1, 2});
      expect(leesSfeer({'nummers': [1]}, 3), isEmpty);
      expect(leesSfeer(null, 3), isEmpty);
    });

    test('DE KERN: Smooth Criminal eruit — het antwoord komt als indexen terug', () async {
      Map<String, dynamic>? verstuurd;
      final ai = AiService(() => 'sk-ant-toets', client: MockClient((v) async {
        verstuurd = jsonDecode(v.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': jsonEncode({'weg': [2]})}
              ],
              'stop_reason': 'end_turn'
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }));
      final weg = await ai.weesSfeer(artiest: 'Sade', titel: 'Cherish the Day', kandidaten: kandidaten);
      expect(weg, {1}, reason: 'Saber: "smooth criminal van michael jackson ?? is niet dezelfde vibe e"');
      expect(jsonEncode(verstuurd), contains('"weg"'), reason: 'het schema vraagt om "weg"');
    });

    test('DE KERN: bij Sade klinkt je albumversie — de radio haalt de single-edit er niet bij', () {
      bool past(String plek, int plekS, String eigen, int eigenS, {required bool elkeLengte}) => eigenPastOpPlek(
          plekTitel: plek,
          plekSeconden: plekS,
          eigenTitel: eigen,
          eigenSeconden: eigenS,
          speling: kRadioSpeling,
          elkeLengte: elkeLengte);
      expect(past('No Ordinary Love (Radio Edit)', 241, 'No Ordinary Love', 440, elkeLengte: true), isTrue,
          reason: 'je had Love Deluxe (7:20), en de radio haalde de edit van 4:01 erbij');
      expect(past('Kiss of Life', 251, 'Kiss of Life', 353, elkeLengte: true), isTrue);
      expect(past('Move On Baby', 220, 'Move On Baby', 291, elkeLengte: false), isFalse,
          reason: 'bij een dance-zaad blijft de lengte tellen — "niet original"');
      expect(past('Freak Out', 230, "Freak Out ('97 Remix)", 215, elkeLengte: true), isFalse,
          reason: 'een remix die je hebt is nooit het origineel');
      expect(past('Kiss of Life', 251, 'Kiss of Life (Mousse T Radio Edit)', 300, elkeLengte: true), isFalse,
          reason: 'een benoemde variant die je hebt is niet vanzelf het origineel — dan telt de lengte');
    });

    test('DE GRENS: zonder sleutel of zonder kandidaten geen vraag', () async {
      var vragen = 0;
      final ai = AiService(() => '', client: MockClient((_) async {
        vragen++;
        return http.Response('{}', 200);
      }));
      expect(await ai.weesSfeer(artiest: 'Sade', kandidaten: kandidaten), isEmpty);
      expect(vragen, 0);
    });
  });

  group('radio vanaf Zombie, 27-09-2026', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_zombie_'));
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });
    File geheugen() => File('${map.path}${Platform.pathSeparator}radiostijl.json');
    const zaad = (familie: Stijlfamilie.rock, jaar: 1993);

    test('DE KERN: wat het model zelf koos, keurt de rocktak niet', () async {
      final b = Stijlboek(
        bestand: geheugen(),
        audioDbGenre: (_) async => 'Rock',
        // Zoals Discogs het die dag gaf: Torn is Pop Rock en Soft Rock, Keep the Faith Hard Rock.
        discogsNummer: (a, t) async => switch (a) {
          'Natalie Imbruglia' => [
              for (var i = 0; i < 3; i++) (jaar: 1997, genres: ['Rock'], stijlen: ['Pop Rock', 'Soft Rock'])
            ],
          'Bon Jovi' => [(jaar: 1992, genres: ['Rock'], stijlen: ['Hard Rock', 'Arena Rock'])],
          _ => const <DiscogsUitgave>[],
        },
      );
      expect((await b.keur('Natalie Imbruglia', 'Torn', zaad, zaadTak: 'alternatief', doorModel: true)).mag,
          isTrue, reason: '"rock, maar klassiek en niet alternatief" — voor een keuze van het model zelf');
      expect((await b.keur('Natalie Imbruglia', 'Torn', zaad, zaadTak: 'alternatief')).mag, isFalse,
          reason: 'van Deezer blijft de tak gewoon keuren');
      expect((await b.keur('Bon Jovi', 'Keep the Faith', zaad, zaadTak: 'alternatief')).mag, isFalse,
          reason: 'daar is de tak voor: Bon Jovi in een Nirvana-radio');
    });

    group('een nee van de tak vóór de lijst van het model', () {
      const nee = (mag: false, waarom: 'rock, maar klassiek en niet alternatief');
      const ja = (mag: true, waarom: 'past');

      test('DE KERN: koos het model het nummer, dan komt het er alsnog in', () async {
        final lijst = Completer<void>();
        final gekozen = <String>{};
        final oordeel = naLijstVanModel(nee,
            zonderTak: () async => ja,
            lijst: lijst.future,
            doorModel: () => gekozen.contains('you oughta know'));
        // Elf seconden later — hier tien milliseconden: het model noemt hem.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        gekozen.add('you oughta know');
        lijst.complete();
        expect((await oordeel).mag, isTrue,
            reason: '"You Oughta Know" viel via Deezer af, en daarna liet de radio de keuze van het model weg');
      });

      test('DE VAL: koos het model hem niet, dan blijft het nee', () async {
        final lijst = Completer<void>()..complete();
        expect((await naLijstVanModel(nee, zonderTak: () async => ja, lijst: lijst.future, doorModel: () => false)).mag,
            isFalse, reason: 'Bon Jovi in een Nirvana-radio blijft eruit');
      });

      test('DE GRENS: een nee van het tijdvak wacht niet op het model', () async {
        final nooit = Completer<void>();
        final o = await naLijstVanModel((mag: false, waarom: 'uit 2003, het zaad is van 1993'),
            zonderTak: () async => (mag: false, waarom: 'uit 2003, het zaad is van 1993'),
            lijst: nooit.future,
            doorModel: () => false,
            geduld: const Duration(hours: 1));
        expect(o.mag, isFalse, reason: 'Keane — anders hield elke afwijzing een haalplek bezet');
      });

      test('DE GRENS: geeft het model niets, dan blijft het nee na het geduld', () async {
        final nooit = Completer<void>();
        final o = await naLijstVanModel(nee,
            zonderTak: () async => ja,
            lijst: nooit.future,
            doorModel: () => false,
            geduld: const Duration(milliseconds: 20));
        expect(o.mag, isFalse);
      });
    });

    test('DE VAL: het jaar van een heruitgave is niet het jaar van het nummer', () async {
      Map<String, dynamic> track(String titel, String album, int id) => {
            'title': titel,
            'artist': {'name': 'Garbage'},
            'album': {'title': album, 'id': id},
            'duration': 259,
            'rank': 680029,
          };
      const albums = {
        1: {'title': 'Garbage (20th Anniversary Edition)', 'release_date': '2015-10-02'},
        2: {'title': 'Garbage', 'release_date': '1995-08-15'},
        3: {'title': 'Absolute Garbage', 'release_date': '2007-07-23'},
      };
      RecommendService deezer(List<Map<String, dynamic>> treffers) => RecommendService(haal: (url) async {
            if (url.contains('/album/')) return albums[int.parse(url.split('/album/').last)];
            return {'data': treffers};
          });
      // Zo stond het die dag bij Deezer: alleen de jubileumuitgave.
      expect(
          await deezer([track('Stupid Girl (Remastered 2015)', 'Garbage (20th Anniversary Edition)', 1)])
              .albumJaar('Garbage', 'Stupid Girl (Remastered 2015)'),
          isNull,
          reason: '"uit 2015, het zaad is van 1993" — een nummer uit 1995');
      // Elk van de twee kenmerken apart: de heruitgave in de naam van het album, en in die van de track.
      expect(await deezer([track('Stupid Girl', 'Garbage (20th Anniversary Edition)', 1)]).albumJaar('Garbage', 'Stupid Girl'),
          isNull);
      expect(
          await deezer([track('Stupid Girl (Remastered 2015)', 'Absolute Garbage', 3)])
              .albumJaar('Garbage', 'Stupid Girl'),
          isNull,
          reason: 'een geremasterde track op een verzamelaar is evenmin van dat jaar');
      expect(
          await deezer([
            track('Stupid Girl (Remastered 2015)', 'Garbage (20th Anniversary Edition)', 1),
            track('Stupid Girl', 'Garbage', 2),
          ]).albumJaar('Garbage', 'Stupid Girl'),
          1995);
      expect(await deezer([track('Stupid Girl', 'Garbage', 2)]).albumJaar('Garbage', 'Stupid Girl'), 1995,
          reason: 'een gewoon album houdt zijn jaar');
    });

    /// Hoe vaak Discogs, Deezer en TheAudioDB opnieuw gevraagd worden na een geheugen van [versie].
    Future<({int discogs, int deezer, int audioDb, bool mag})> naVersie(int versie) async {
      geheugen().writeAsStringSync(jsonEncode({
        '_versie': versie,
        'n:garbage|onlyhappywhenitrains': {'f': ['rock'], 'j': 1995, 's': <String>[], 't': null},
        'd:garbage|stupidgirlremastered2015': 2015,
        'a:garbage': 'rock',
      }));
      var discogs = 0, deezer = 0, audioDb = 0;
      final b = Stijlboek(
        bestand: geheugen(),
        audioDbGenre: (_) async {
          audioDb++;
          return 'Rock';
        },
        discogsNummer: (a, t) async {
          discogs++;
          return const <DiscogsUitgave>[];
        },
        deezerJaar: (a, t) async {
          deezer++;
          return null;
        },
      );
      await b.nummer('Garbage', 'Only Happy When It Rains');
      final mag = (await b.keur('Garbage', 'Stupid Girl (Remastered 2015)', zaad)).mag;
      return (discogs: discogs, deezer: deezer, audioDb: audioDb, mag: mag);
    }

    test('DE GRENS: een geheugen van versie 2 vergeet het Deezer-jaar, en nooit het genre', () async {
      final n = await naVersie(2);
      expect(n.deezer, 1, reason: 'onder versie 2 onthouden als 2015 — dan bleef hij voorgoed "uit 2015"');
      expect(n.mag, isTrue);
      expect(n.audioDb, 0, reason: 'het genre van een artiest is nog waar — en elke vraag kost drie seconden');
    });

    test('DE GRENS: een geheugen van versie 3 vergeet de nummers, niet het Deezer-jaar', () async {
      final n = await naVersie(3);
      expect(n.discogs, 2, reason: 'onder versie 3 telde een heruitgave nog voor het jaar — The Drugs Don\'t Work "uit 2017"');
      expect(n.deezer, 0, reason: 'het Deezer-jaar volgde onder versie 3 al de nieuwe regel');
      expect(n.audioDb, 0);
    });

    test('DE GRENS: een geheugen van versie 4 vergeet de nummers, niet het Deezer-jaar', () async {
      final n = await naVersie(4);
      expect(n.discogs, 2, reason: 'onder versie 4 telde een plaat die het nummer niet draagt — U2 "One" 1983');
      expect(n.deezer, 0);
      expect(n.audioDb, 0);
    });

    test('DE VAL: een heruitgave telt voor de stijl, niet voor het jaar', () {
      // Zo gaf Discogs het op 27-09-2026 voor "The Verve — The Drugs Don't Work", met apostrof.
      Map<String, dynamic> regel(String jaar, List<String> formaat, {String titel = 'The Verve - Urban Hymns'}) => {
            'title': titel,
            'year': jaar,
            'format': formaat,
            'genre': ['Rock'],
            'style': ['Alternative Rock', 'Britpop'],
          };
      final heruitgaven = [
        for (final f in [
          ['CD', 'Album', 'Reissue', 'Remastered', 'Box Set'],
          ['File', 'AAC', 'Compilation', 'Remastered'],
          ['CDr', 'Deluxe Edition', 'Promo', 'Reissue'],
        ])
          uitgaveUitZoekregel(regel('2017', f), 'The Verve')!
      ];
      expect([for (final u in heruitgaven) u.jaar], [null, null, null], reason: '"uit 2017, het zaad is van 1993"');
      expect(heruitgaven.first.stijlen, contains('Britpop'), reason: 'de stijl van een heruitgave is nog waar');
      expect(genoegVoorEenJaar(heruitgaven), isFalse,
          reason: 'dan wordt de vrije zoekvraag ook gesteld — en die vindt de uitgaven van 1997');
      final origineel = uitgaveUitZoekregel(regel('1997', ['CD', 'Single']), 'The Verve')!;
      expect(origineel.jaar, 1997);
      expect(genoegVoorEenJaar([origineel, origineel, origineel]), isTrue);
      expect(uitgaveUitZoekregel(regel('1997', ['CD', 'Compilation', 'Unofficial Release']), 'The Verve'), isNull,
          reason: 'een bootleg telt nergens voor');
      expect(uitgaveUitZoekregel(regel('1968', ['LP'], titel: 'Leon Sash - Sash!'), 'Sash!'), isNull,
          reason: 'het artiestveld zoekt op een deel van de naam');
    });

    group('U2 "One": Discogs zoekt op woorden', () {
      // De tracklijst van War (1983), zoals Discogs hem gaf.
      const war = [
        'Sunday Bloody Sunday', 'Seconds', "New Year's Day", 'Like A Song...', 'Drowning Man', 'The Refugee',
        'Two Hearts Beat As One', 'Red Light', 'Surrender', '"40"',
      ];
      Zoekregel regel(int id, String plaat, int jaar) =>
          (uitgave: (jaar: jaar, genres: const ['Rock'], stijlen: const <String>[]), id: id, plaat: plaat);

      test('DE VAL: "One" is niet "Two Hearts Beat As One"', () {
        expect(draagtNummer(war, 'One'), isFalse, reason: '"uit 1983, het zaad is van 1993" — One is van 1991');
        expect(draagtNummer(['Zoo Station', 'Even Better Than The Real Thing', 'One'], 'One'), isTrue);
        expect(draagtNummer(['Open', 'High', 'Friday I´m In Love'], "Friday I'm in Love"), isTrue,
            reason: 'Wish schrijft een ander apostrof');
        expect(draagtNummer(["La Cafetería De Tom = Tom's Diner", 'Luka'], "Tom's Diner"), isTrue,
            reason: 'de Spaanse persing van Solitude Standing');
        expect(draagtNummer(['La Cena De Tom "Tom\'s Diner"'], "Tom's Diner"), isTrue);
        expect(draagtNummer(['Zombie (Radio Edit)', 'Away'], 'Zombie'), isTrue);
      });

      test('DE KERN: drie platen zonder het nummer, dan telt de hele bladzijde niet', () async {
        final tracklijst = <int, List<String>>{
          1: war,
          2: ['Sunday Bloody Sunday', 'Two Hearts Beat As One'],
          3: ['Two Hearts Beat As One', 'Endless Deep'],
          4: ["New Year's Day", 'Treasure (Whatever Happened To Pete The Chop)'],
          9: ['Zoo Station', 'One', 'Until The End Of The World'],
        };
        final gevraagd = <int>[];
        Future<List<String>?> tracks(int id) async {
          gevraagd.add(id);
          return tracklijst[id];
        }

        // Zo gaf Discogs het: alleen 1983, vier platen, War in meer persingen.
        final bladzijde = [
          regel(1, 'u2 - war', 1983),
          regel(11, 'u2 - war', 1983),
          regel(2, 'u2 - sunday bloody sunday', 1983),
          regel(3, 'u2 - two hearts beat as one', 1983),
          regel(4, "u2 - new year's day", 1983),
        ];
        expect(await metHetNummer(bladzijde, 'One', tracks), isEmpty,
            reason: 'dan vindt de vrije zoekvraag het wel');
        expect(gevraagd, hasLength(3), reason: 'hoogstens drie platen');
        expect(gevraagd, isNot(contains(11)), reason: 'War maar één keer, niet elke persing');

        gevraagd.clear();
        final vrij = await metHetNummer([regel(4, "u2 - new year's day", 1983), regel(9, 'u2 - achtung baby', 1991)],
            'One', tracks);
        expect(vroegsteJaar([for (final u in vrij!) u.jaar]), 1991);
        expect(gevraagd, [4, 9]);
      });

      test('DE GRENS: meestal is één blik genoeg, en zonder antwoord onthoudt niemand iets', () async {
        var gevraagd = 0;
        final zombie = [
          regel(20, 'the cranberries - no need to argue', 1994),
          regel(21, 'the cranberries - zombie', 1994),
          regel(22, 'the cranberries - zombie', 1995),
        ];
        final z = await metHetNummer(zombie, 'Zombie', (id) async {
          gevraagd++;
          return ['Ode To My Family', 'Zombie'];
        });
        expect(z, hasLength(3));
        expect(gevraagd, 1, reason: 'bij 168 van 193 nummers van het model klopte de eerste plaat meteen');
        expect(await metHetNummer(zombie, 'Zombie', (id) async => null), isNull,
            reason: 'een half antwoord wordt niet bewaard');
      });
    });

    test('DE KERN: wat het model koos en voor de helft rock is, is rock', () async {
      // Zo gaf Discogs "The Corrs — Runaway" op 27-09-2026: negen uitgaven, zes met Rock, acht met Pop,
      // alle negen met Folk.
      const zonder = <String>[];
      final corrs = <DiscogsUitgave>[
        (jaar: 1995, genres: ['Pop', 'Folk, World, & Country'], stijlen: zonder),
        (jaar: 1995, genres: ['Rock', 'Pop'], stijlen: ['Folk Rock', 'Soft Rock', 'Pop Rock']),
        (jaar: 1995, genres: ['Rock'], stijlen: ['Folk Rock']),
        (jaar: 1995, genres: ['Rock', 'Pop'], stijlen: ['Folk Rock', 'Soft Rock', 'Pop Rock']),
        (jaar: 1995, genres: ['Rock', 'Pop'], stijlen: ['Folk Rock', 'Soft Rock', 'Pop Rock']),
        (jaar: 1995, genres: ['Pop', 'Folk, World, & Country'], stijlen: zonder),
        (jaar: 1995, genres: ['Rock', 'Pop'], stijlen: ['Folk Rock', 'Soft Rock', 'Pop Rock']),
        (jaar: 1995, genres: ['Rock', 'Pop'], stijlen: ['Folk Rock', 'Soft Rock', 'Pop Rock']),
        (jaar: 1995, genres: ['Pop', 'Folk, World, & Country'], stijlen: zonder),
      ];
      // Everything But The Girl "Missing": vooral dance, rock op drie van de negen.
      final missing = <DiscogsUitgave>[
        for (var i = 0; i < 6; i++) (jaar: 1994, genres: ['Electronic'], stijlen: ['House']),
        for (var i = 0; i < 3; i++) (jaar: 1994, genres: ['Rock', 'Pop'], stijlen: ['Soft Rock']),
      ];
      final b = Stijlboek(
        bestand: geheugen(),
        audioDbGenre: (a) async => a == 'The Corrs' ? 'Country' : 'Electronic',
        discogsNummer: (a, t) async => switch (a) {
          'The Corrs' => corrs,
          'Everything But The Girl' => missing,
          _ => const <DiscogsUitgave>[],
        },
      );
      expect((await b.keur('The Corrs', 'Runaway', zaad, zaadTak: 'alternatief', doorModel: true)).mag, isTrue,
          reason: '"stijl country, niet rock" — zes van de negen uitgaven zijn rock');
      // Zonder tak, zodat alleen de familie spreekt.
      final vanDeezer = await b.keur('The Corrs', 'Runaway', zaad);
      expect(vanDeezer.mag, isFalse, reason: 'wat Deezer erbij doet, keurt de meerderheid nog');
      expect(vanDeezer.waarom, startsWith('stijl'));
      expect(
          (await b.keur('Everything But The Girl', 'Missing', zaad, zaadTak: 'alternatief', doorModel: true)).mag,
          isFalse,
          reason: 'drie van de negen is geen helft');
      expect(minstensDeHelft([
        {Stijlfamilie.rock},
        {Stijlfamilie.popsoul},
      ]), {Stijlfamilie.rock, Stijlfamilie.popsoul}, reason: 'precies de helft telt');
    });

    test('DE VAL: een pianoversie is geen single', () {
      expect(uitvoeringVan('What’s Up! (piano version)'), Uitvoering.bewerking);
      expect(
          klopt('4 Non Blondes', "What's Up? (Single Version)",
              r'Muziek\4 Non Blondes - What’s Up!\4 Non Blondes - What’s Up! - 04 - What’s Up! (piano version).flac'),
          isFalse,
          reason: 'zo kwam hij binnen voor de single');
      expect(klopt('4 Non Blondes', "What's Up?", r'4 Non Blondes\Bigger, Better, Faster, More!\02 - What’s Up.flac'),
          isTrue);
      expect(uitvoeringVan('Piano Man'), Uitvoering.origineel, reason: 'alleen de staart telt');
      expect(klopt('Christina Aguilera', 'Beautiful', r'Christina Aguilera\Stripped\11 - Beautiful.flac'), isTrue,
          reason: 'Stripped is het album, geen uitvoering');
    });

    test('DE VAL: een radio-uitzending is een live-opname, geen radio-edit', () {
      const uitzending = 'Smells Like Teen Spirit (Broadcast from Italy) (Remastered Radio Recording)';
      expect(uitvoeringVan(uitzending), Uitvoering.bewerking);
      const treffers = <_T>[
        (artiest: 'Nirvana', titel: 'Smells Like Teen Spirit', rang: 985641, seconden: 301),
        (artiest: 'Nirvana', titel: 'Smells Like Teen Spirit (Live In Del Mar, California/1991)', rang: 580810, seconden: 289),
        (artiest: 'Nirvana', titel: uitzending, rang: 120000, seconden: 290),
      ];
      expect(besteTreffer(treffers, 'Nirvana', 'Smells Like Teen Spirit'), 0,
          reason: 'het woord "Radio" maakte de uitzending de gevraagde versie, boven die van Nevermind');
      expect(uitvoeringVan('Smells Like Teen Spirit (Radio Edit)'), Uitvoering.radio);
      expect(uitvoeringVan('Rhythm Is a Dancer (Radio)'), Uitvoering.radio);
      expect(uitvoeringVan('Stupid Girl (Remastered 2015)'), Uitvoering.origineel);
    });

    test('DE KERN: geen antwoord van Deezer is niet "niet gevonden"', () async {
      var keer = 0;
      final log = <String>[];
      final deezer = RecommendService(
          adem: Duration.zero,
          haal: (url) async {
            if (keer++ == 0) throw const DeezerFout('Quota limit exceeded', quota: true);
            return {
              'data': [
                {
                  'title': 'Iris',
                  'artist': {'name': 'The Goo Goo Dolls'},
                  'album': {'title': 'Dizzy up the Girl', 'id': 1},
                  'duration': 289,
                  'rank': 900000,
                }
              ]
            };
          });
      final uit = await deezer.lijstOpDeezer([AiNummer('Goo Goo Dolls', 'Iris')], spoor: log.add);
      expect([for (final t in uit) t.title], ['Iris'],
          reason: 'Iris, Lovefool en Closing Time heetten "niet gevonden" — Deezer kent ze alle drie');
      expect(log.last, isNot(contains('niet gevonden')));
    });

    test('DE GRENS: wat blijft zwijgen staat als "geen antwoord" in het logboek, niet als "niet gevonden"', () async {
      var keer = 0;
      final log = <String>[];
      final deezer = RecommendService(
          adem: Duration.zero,
          haal: (url) async {
            keer++;
            throw const DeezerFout('Deezer gaf 503');
          });
      expect(await deezer.lijstOpDeezer([AiNummer('Goo Goo Dolls', 'Iris')], spoor: log.add), isEmpty);
      expect(keer, 2, reason: 'één keer opnieuw, niet eindeloos');
      expect(log.last, contains('geen antwoord: Goo Goo Dolls — Iris (Deezer gaf 503)'));
      expect(log.last, isNot(contains('niet gevonden')));
    });
  });
}
