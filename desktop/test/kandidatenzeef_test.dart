/// De titelzeef van "Ontbrekende downloaden", buiten de UI-draad.
///
/// **Waarom.** Op de S26 stond de UI-draad 2078 ms stil na "Ontbrekende downloaden" op *Morning
/// Glory* (warmte.log, 11-10-2026): elf nummers, elk gezeefd over de hele albumbrede zoeklijst, in één
/// blok. En de catalogusalbumpagina zeefde diezelfde lijst opnieuw bij elke opbouw van elke rij.
library;

import 'dart:async';
import 'dart:io';

import 'package:debridmusic/kandidatenzeef.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

const _titels = [
  'Hello', 'Roll With It', 'Wonderwall', "Don't Look Back in Anger", 'Hey Now!', 'Some Might Say',
  'Cast No Shadow', "She's Electric", 'Morning Glory', 'Champagne Supernova',
];

List<SoulseekFile> _albumbreed(int peers) => [
      for (var u = 0; u < peers; u++)
        for (var i = 0; i < _titels.length; i++)
          SoulseekFile(
            username: 'peer$u',
            filename: '@@peer$u\\Music\\Oasis\\(What\'s The Story) Morning Glory (1995)\\'
                '${(i + 1).toString().padLeft(2, '0')} - ${_titels[i]}.${u.isEven ? 'flac' : 'mp3'}',
            size: 30000000,
            speed: 1000000,
            queueLength: 0,
            freeSlots: true,
            durationSec: 240 + i,
          ),
    ];

void main() {
  test('in de isolate komt precies hetzelfde uit als ter plekke', () async {
    final lijst = _albumbreed(60); // 600 bestanden
    for (final t in ['Wonderwall', 'Morning Glory']) {
      final nu = zeefKandidatenNu(lijst, titel: t, seconden: 242, artiest: 'Oasis', album: "(What's The Story) Morning Glory?");
      final apart = await zeefKandidaten(lijst, titel: t, seconden: 242, artiest: 'Oasis', album: "(What's The Story) Morning Glory?");
      expect(apart.map((f) => f.filename), nu.map((f) => f.filename));
      expect(nu, isNotEmpty, reason: 'anders bewijst de vergelijking niets');
    }
  });

  test('DE KERN: een grote lijst houdt de draad niet vast', () async {
    // Een klok die elke 10 ms tikt. Zeeft de draad zelf 4400 bestanden, dan tikt hij al die tijd niet.
    final lijst = _albumbreed(440);
    var tikken = 0;
    final klok = Timer.periodic(const Duration(milliseconds: 10), (_) => tikken++);
    final sw = Stopwatch()..start();
    for (final t in _titels) {
      await zeefKandidaten(lijst, titel: t, seconden: 240, artiest: 'Oasis', album: "(What's The Story) Morning Glory?");
    }
    sw.stop();
    klok.cancel();
    // Minstens de helft van de tikken die in die tijd hadden moeten vallen.
    expect(tikken, greaterThanOrEqualTo(sw.elapsedMilliseconds ~/ 20),
        reason: '${sw.elapsedMilliseconds} ms gezeefd en maar $tikken tikken: de draad zat vast');
  });

  test('ook een korte lijst, en alleen het gevraagde nummer', () async {
    final lijst = _albumbreed(2);
    final uit = await zeefKandidaten(lijst, titel: 'Hello', seconden: 240, artiest: 'Oasis');
    expect(uit.map((f) => f.username).toSet(), {'peer0', 'peer1'});
  });

  test('beide albumpagina\'s gebruiken de zeef, en de catalogus onthoudt hem per titel', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main.contains('Future<List<SoulseekFile>> zeef(List<SoulseekFile> files) => zeefKandidaten(files,'),
        isTrue, reason: '"Ontbrekende downloaden" zeeft buiten de UI-draad');
    // Sinds 23-10-2026 rekent de telling naast elke rij helemaal niet meer in `build` (Mac: beelden van 6,2 s).
    final rij = main.substring(main.indexOf('  List<SoulseekFile> _slskForTitle(CatalogTrack t) {'));
    expect(rij.substring(0, rij.indexOf('\n  }\n')), isNot(contains('zeefKandidatenNu')),
        reason: 'de telling naast elke rij zeeft niet meer op de UI-draad');
    expect(main, contains('    return _slskPerTitel[\'\${t.title}|\${t.durationSec}\'] ?? const [];'));
    expect(main, contains('            : await zeefPerTitel(lijst, [for (final t in sporen)'),
        reason: 'alle titels samen, buiten de UI-draad');
    expect(main, contains('  bool get _zeefKlaar => identical(_slskPerTitelVan, _albumSlsk) && identical(_slskPerTitelSporen, _tracks);'),
        reason: 'een nieuw zoekresultaat (of een andere tracklijst) laat opnieuw zeven');
    expect(main, contains('      while (mounted && !_zeefKlaar) {'),
        reason: 'kwam er intussen een nieuwe tussenstand, dan nog eens met de nieuwste');
  });

  test('per titel in één keer: dezelfde bestanden als de zeef per nummer, als plekken in de lijst', () async {
    final lijst = _albumbreed(6);
    final titels = [for (final t in _titels) (titel: t, seconden: 240)];
    final plekken = await zeefPerTitel(lijst, titels, artiest: 'Oasis', album: '(What\'s the Story) Morning Glory?');
    expect(plekken, hasLength(_titels.length));
    for (var i = 0; i < _titels.length; i++) {
      final los = zeefKandidatenNu(lijst,
          titel: _titels[i], seconden: 240, artiest: 'Oasis', album: '(What\'s the Story) Morning Glory?');
      expect([for (final p in plekken[i]) lijst[p]], los, reason: _titels[i]);
      expect(los, isNotEmpty, reason: 'anders bewijst dit niets: ${_titels[i]}');
    }
  });

  group('een gast in de titel die de bestanden niet noemen', () {
    SoulseekFile f(String pad, int sec, {String peer = 'p'}) => SoulseekFile(
        username: peer, filename: pad, size: 30000000, speed: 1000000, queueLength: 0, freeSlots: true, durationSec: sec);
    // Letterlijk wat Soulseek op 15-10-2026 gaf voor "amel bent 20 ans".
    final amel = [
      f(r'music\Amel Bent\A 20 ans [2007]\03. A 20 Ans.flac', 231, peer: 'a'),
      f(r'music\Amel Bent\A 20 ans [2007]\02. J' "'" r'ai Changé D' "'" r'avis.flac', 208, peer: 'a'),
      f(r'downloads\Musique\Flac\Français\Amel Bent\Amel Bent - A 20 ans [2007]\03. A 20 Ans.flac', 231, peer: 'b'),
      f(r'downloads\Musique\Flac\Français\Amel Bent\Amel Bent - A 20 ans [2007]\14. Tu N' "'" r'es Plus Là (Version piano voix).flac', 258, peer: 'b'),
    ];
    const titel = "À 20 ans (feat. Diam's)";

    test('Amel Bent: het bestand uit de albummap komt nu door, bij elke peer', () {
      final uit = zeefKandidatenNu(amel, titel: titel, seconden: 231, artiest: 'Amel Bent', album: 'À 20 ans');
      expect(uit.map((x) => x.username), ['a', 'b']);
      expect(uit.every((x) => x.filename.endsWith('03. A 20 Ans.flac')), isTrue);
    });

    test('maar niet buiten een map die het album noemt', () {
      final los = [f(r'Diversen\Franse hits\A 20 Ans.flac', 231)];
      expect(zeefKandidatenNu(los, titel: titel, seconden: 231, artiest: 'Amel Bent', album: 'À 20 ans'), isEmpty);
    });

    test('en niet met een lengte die meer dan 3 s afwijkt', () {
      final ander = [f(r'music\Amel Bent\A 20 ans [2007]\03. A 20 Ans.flac', 236)];
      expect(zeefKandidatenNu(ander, titel: titel, seconden: 231, artiest: 'Amel Bent', album: 'À 20 ans'), isEmpty);
    });

    test('en niet als dezelfde map de versie mét gast apart heeft — dan is het kale bestand de solo', () {
      // Adele: "Easy On Me" solo én als duet op dezelfde plaat.
      final adele = [
        f(r'Adele\30 (Deluxe)\01 Easy On Me.flac', 224),
        f(r'Adele\30 (Deluxe)\13 Easy On Me (feat. Chris Stapleton).mp3', 225),
      ];
      final uit = zeefKandidatenNu(adele,
          titel: 'Easy On Me (feat. Chris Stapleton)', seconden: 225, artiest: 'Adele', album: '30 (Deluxe)');
      expect(uit.map((x) => x.filename), [r'Adele\30 (Deluxe)\13 Easy On Me (feat. Chris Stapleton).mp3'],
          reason: 'de strenge zeef vindt het duet; de solo komt er nooit bij');
      // Een albumnaam met een woord erin, anders staat de terugval al uit voor deze regel aan bod komt
      // (een titel als "30" geeft geen woord om de map aan te herkennen).
      final zonderDuet = zonderGast([
        f(r'Adele\Thirty (Deluxe)\01 Easy On Me.flac', 224),
        f(r'Adele\Thirty (Deluxe)\13 Easy On Me (feat. Chris Stapleton).flac', 260),
      ], titel: 'Easy On Me (feat. Chris Stapleton)', seconden: 224, artiest: 'Adele', album: 'Thirty (Deluxe)');
      expect(zonderDuet, isEmpty, reason: 'de map draagt de gast in een andere naam: het kale bestand is de solo');
      expect(
          zonderGast([f(r'Adele\Thirty (Deluxe)\01 Easy On Me.flac', 224)],
              titel: 'Easy On Me (feat. Chris Stapleton)', seconden: 224, artiest: 'Adele', album: 'Thirty (Deluxe)'),
          hasLength(1),
          reason: 'zonder aparte gastversie in de map wel — dat is het geval van Amel Bent');
    });

    test('de knop op de catalogusalbumpagina gaat door dezelfde zeef', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final s = main.indexOf('Future<List<SoulseekFile>> _slskCandidatesForTrack(');
      final e = main.indexOf('Future<void> _downloadTrack(', s);
      final bron = main.substring(s, e);
      // Via de vroege start ([SoulseekService.zoekVroeg]), maar door dezelfde zeef — ook de tussenstand.
      expect(bron, contains('zeef: (l) => zeefKandidaten(l,'));
      expect(bron, isNot(contains('fileOffersTitle(')));
    });
  });

  // Live — V (15-10-2026): naast "Intro" (0:37) 16 bronnen, de meeste intro's van live-albums van
  // anderen. Op het bewaarde antwoord van "Live V 2001" bleven er na deze regel 11, alle uit een V-map.
  // Saber, 24-10-2026, Céline Dion *D'eux*: "J'irai où tu iras (with Jean-Jacques Goldman)" had 14 bronnen, de andere
  // nummers rond de 230. "Dat mag er zeker bij staan, maar voor soulseek resultaten … hij moet enkel de titel zien."
  group('een duet dat maar één keer op de plaat staat: alleen de titel telt', () {
    SoulseekFile f(String pad, int sec, {String peer = 'p'}) => SoulseekFile(
        username: peer, filename: pad, size: 30000000, speed: 1000000, queueLength: 0, freeSlots: true, durationSec: sec);
    const duet = "J'irai où tu iras (with Jean-Jacques Goldman)";
    const deux = [
      'Pour que tu m\'aimes encore', 'Le Ballet', 'Regarde-moi', 'Je sais pas', 'La Mémoire d\'Abraham',
      'Cherche encore', 'Destin', 'Les derniers seront les premiers', duet, "J'attendais", 'Prière païenne', 'Vole',
    ];
    final bestanden = [
      for (var u = 0; u < 10; u++) f('@@peer$u\\Music\\Celine Dion\\D\'eux (1995)\\09 - J\'irai ou tu iras.flac', 207, peer: 'k$u'),
      for (var u = 0; u < 2; u++)
        f('@@gast$u\\Celine Dion - D\'eux\\09 Celine Dion - J\'irai ou tu iras (with Jean-Jacques Goldman).flac', 207,
            peer: 'g$u'),
      f('@@peerX\\Celine Dion\\D\'eux (1995)\\03 - Regarde-moi.flac', 237, peer: 'x'),
    ];

    test('DE KERN: met de tracklijst tellen ook de bestanden met alleen de titel — 12 en niet 2', () {
      final uit = zeefPerTitelNu(bestanden, [for (final t in deux) (titel: t, seconden: t == duet ? 207 : 237)],
          artiest: 'Céline Dion', album: "D'eux");
      expect(uit[deux.indexOf(duet)], hasLength(12));
      expect(uit[deux.indexOf('Regarde-moi')], [bestanden.length - 1], reason: 'de andere nummers blijven wat ze waren');
    });

    test('zonder tracklijst (een los nummer) blijft het zoals het was: de strenge zeef, en pas bij niets de terugval', () {
      final uit = zeefKandidatenNu(bestanden, titel: duet, seconden: 207, artiest: 'Céline Dion', album: "D'eux");
      expect(uit.map((x) => x.username), ['g0', 'g1']);
    });

    test('DE GRENS: staat dezelfde titel ook solo op de plaat (Adele), dan blijft de gast het verschil', () {
      expect(alleenDeTitel('Easy On Me (with Chris Stapleton)', ['Easy On Me', 'My Little Love', 'Easy On Me (with Chris Stapleton)']),
          isNull);
      expect(alleenDeTitel(duet, deux), "J'irai où tu iras");
      final adele = [
        f(r'Adele\30 (Deluxe)\01 Easy On Me.flac', 224),
        f(r'Adele\30 (Deluxe)\13 Easy On Me (with Chris Stapleton).flac', 225),
      ];
      final uit = zeefPerTitelNu(adele, [(titel: 'Easy On Me', seconden: 224), (titel: 'Easy On Me (with Chris Stapleton)', seconden: 225)],
          artiest: 'Adele', album: '30 (Deluxe)');
      expect(uit[1], [1], reason: 'het duet: alleen het bestand met de gast, nooit de solo');
    });

    test('DE VAL: een kaal bestand naast de gastversie in dezelfde map is daar de solo', () {
      final map = [
        f(r"@@a\Celine Dion\Duos\05 - J'irai ou tu iras (with Jean-Jacques Goldman).flac", 207),
        f(r"@@a\Celine Dion\Duos\06 - J'irai ou tu iras.flac", 207),
      ];
      final uit = zeefKandidatenNu(map, titel: duet, seconden: 207, artiest: 'Céline Dion', album: "D'eux", albumTitels: deux);
      expect(uit.map((x) => x.filename), [map[0].filename]);
    });

    test('"(with …)" is een gast — behalve strijkers, een orkest, een koor of een versie; en nooit midden in de titel', () {
      expect(alleenDeTitel('Song (with Ellie Goulding)', const ['Song (with Ellie Goulding)']), 'Song');
      expect(alleenDeTitel('Song (with Strings)', const ['Song (with Strings)']), isNull);
      expect(alleenDeTitel('Song (with The Royal Philharmonic Orchestra)', const ['x']), isNull);
      expect(alleenDeTitel('Song (with X Remix)', const ['x']), isNull);
      expect(alleenDeTitel('Dance With Me', const ['x']), isNull);
      expect(alleenDeTitel('À 20 ans (feat. Diam\'s)', const ['x']), 'À 20 ans', reason: 'feat. blijft wat het was');
    });

    test('accenten tellen niet: "Prière païenne" en "où" passen op een bestandsnaam zonder accent, en omgekeerd', () {
      final zonder = [f(r"@@p\Celine Dion\D'eux (1995)\11 - Priere paienne.flac", 252)];
      final met = [f(r"@@p\Celine Dion\D'eux (1995)\11 - Prière païenne.flac", 252)];
      expect(zeefKandidatenNu(zonder, titel: 'Prière païenne', seconden: 252, artiest: 'Céline Dion', album: "D'eux"), hasLength(1));
      expect(zeefKandidatenNu(met, titel: 'Priere paienne', seconden: 252, artiest: 'Celine Dion', album: "D'eux"), hasLength(1));
      expect(zeefKandidatenNu(zonder, titel: 'Vole', seconden: 252, artiest: 'Céline Dion', album: "D'eux"), isEmpty,
          reason: 'een ander nummer blijft een ander nummer');
    });

    test('beide plekken op de albumpagina geven de tracklijst mee', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(RegExp(r'albumTitels: albumTitels\)').allMatches(main).length, greaterThanOrEqualTo(2));
      final zeef = File('lib/kandidatenzeef.dart').readAsStringSync();
      expect(zeef, contains('final albumTitels = [for (final t in titels) t.titel];'));
    });
  });

  group('een titel als "Intro"', () {
    SoulseekFile f(String pad, int sec) => SoulseekFile(
        username: 'p', filename: pad, size: 1000000, speed: 1000, queueLength: 0, freeSlots: true, durationSec: sec);

    test('telt alleen in een map die het album noemt, ook een album van één letter', () {
      final uit = zeefKandidatenNu([
        f(r'music\Live\V (2001)\Live - V - 01 - Intro.flac', 37),
        f(r'music\Live\[2001] V\01 - Intro.mp3', 37),
        f(r'music\Iemand\Live at Wembley\01 Intro.flac', 40),
        f(r'music\Live\Live at the Paradiso\01 Intro.flac', 38),
      ], titel: 'Intro', seconden: 37, artiest: 'Live', album: 'V');
      expect([for (final x in uit) x.filename], [
        r'music\Live\V (2001)\Live - V - 01 - Intro.flac',
        r'music\Live\[2001] V\01 - Intro.mp3',
      ]);
    });

    test('een gewone titel blijft zoals hij was', () {
      expect(algemeneTitelZonderAlbum('Overcome', 'V', r'music\Top 100 Van 2001\035 - Live - Overcome.flac'), isFalse);
      expect(algemeneTitelZonderAlbum('Intro', 'V', r'music\Top 100 Van 2001\001 - Intro.flac'), isTrue);
      expect(algemeneTitelZonderAlbum('Interlude', 'Lemonade', r'Beyonce\Lemonade\05 Interlude.flac'), isFalse);
      expect(algemeneTitelZonderAlbum('Intro', null, r'x\01 Intro.flac'), isFalse, reason: 'zonder album geen regel');
    });
  });

  // Saber, 25-10-2026, met SoulseekQt ernaast: "is de filter ergens niet te streng ????". De uitgave op de albumpagina
  // zei 2:55 (175 s); de kopieën, ook in mappen "Jonas Brothers (2007)", 3:18–3:19 (Deezer: 198 s).
  group('de lengte van de meerderheid', () {
    SoulseekFile f(String peer, String pad, int? sec) => SoulseekFile(
        username: peer, filename: pad, size: 26806672, speed: 1000000, queueLength: 0, freeSlots: true, durationSec: sec);
    final kids = [
      for (var i = 0; i < 30; i++)
        f('jb$i', 'music\\Jonas Brothers (2007)\\Jonas Brothers\\14 - Kids Of The Future.flac', i.isEven ? 199 : 198),
      for (var i = 0; i < 6; i++) f('mtr$i', 'Danny Elfman - Meet the Robinsons (FLAC)\\18 - Kids of the Future - Jonas Brothers.flac', 350),
      f('karaoke', 'Artist Karaoke Series\\Jonas Brothers_Artist Karaoke Series_08_Kids Of The Future.flac', 216),
      f('Tiigripoiss99', 'jonas brothers\\03 - Kids Of The Future.flac', null),
      f('Noxonix', 'Jonas Brothers\\Kids Of The Future.mp3', null),
    ];

    test('DE KERN: de kopieën zijn het eens over 3:19 — dan geldt die, en komen de FLAC\'s door de zeef', () {
      expect(lengteVanDeMeerderheid(kids, 175), 199);
      final door = zeefKandidatenNu(kids, titel: 'Kids Of The Future', seconden: 175, artiest: 'Jonas Brothers');
      expect(door.where((x) => x.durationSec == 199 || x.durationSec == 198), hasLength(30));
      expect(door.where((x) => x.durationSec == 350), isEmpty, reason: '5:50 is iets anders');
      expect(door.where((x) => x.durationSec == null), hasLength(2), reason: 'zonder lengte blijft het zoals het was');
    });

    test('hebben drie uploaders de officiële lengte, dan blijft die — een radio-edit naast de albumversie', () {
      final edit = [
        for (var i = 0; i < 20; i++) f('lp$i', 'Artiest\\Album\\05 Nummer.flac', 262),
        for (var i = 0; i < 3; i++) f('edit$i', 'Artiest\\Single\\01 Nummer (Radio Edit).flac', 210),
      ];
      expect(lengteVanDeMeerderheid(edit, 210), isNull);
    });

    test('te weinig stemmen, geen meerderheid, of dichtbij de officiële: niets', () {
      expect(lengteVanDeMeerderheid(kids.take(7), 175), isNull, reason: 'zeven uploaders is te weinig');
      final verdeeld = [
        for (var i = 0; i < 9; i++) f('a$i', 'x\\Nummer.flac', 199),
        for (var i = 0; i < 10; i++) f('b$i', 'x\\Nummer.flac', 240),
        for (var i = 0; i < 10; i++) f('c$i', 'x\\Nummer.flac', 300),
      ];
      expect(lengteVanDeMeerderheid(verdeeld, 175), isNull, reason: 'geen groep heeft de helft');
      expect(lengteVanDeMeerderheid(kids, 190), isNull, reason: 'binnen 12 s: de gewone marge vangt het op');
      expect(lengteVanDeMeerderheid(kids, null), isNull);
    });

    // Gemeten op 26-10-2026: 1006 kopieën met de titel, geen enkele van de 3:20 die Deezer zegt, verspreid over 4:56–5:08.
    test('Foreigner: verspreid over 4:56–5:08, geen enkele met de Deezer-lengte — dan toch de lengte van de kopieën', () {
      final foreigner = [
        for (var i = 0; i < 40; i++) f('a$i', r'Foreigner\Agent Provocateur\06 - I Want to Know What Love Is.flac', 296 + (i % 3)),
        for (var i = 0; i < 60; i++) f('b$i', r'Foreigner\Agent Provocateur\06 - I Want to Know What Love Is.flac', 300 + (i % 5)),
        for (var i = 0; i < 50; i++) f('c$i', r'Foreigner\Records\I Want to Know What Love Is.flac', 305 + (i % 4)),
      ];
      expect(lengteVanDeMeerderheid(foreigner, 200), inInclusiveRange(296, 308));
      expect(kMeerderheidVenster, 8);
    });

    test('één uploader stemt één keer per lengte', () {
      final een = [for (var i = 0; i < 20; i++) f('zelfde', 'x\\$i Kids Of The Future.flac', 199)];
      expect(lengteVanDeMeerderheid(een, 175), isNull);
    });

    test('aangesloten: de bronnenlijst en de download gebruiken dezelfde lengte', () {
      final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(m, contains('    final lengte = lengteVanDeMeerderheid(metTitel, t.seconds) ?? t.seconds;\n'));
      expect(m, contains('    return _klaar = _SlskKlaar.van(_slsk, _filter, past: past, hergebruik: zelfde ? '));
      final o = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(o, contains('      final lengte = lengteVanDeMeerderheid(candidates, gezag.seconds);\n'));
      expect(o, contains('        authority = gezag.metSeconden(lengte);\n'), reason: 'ook de keuring na de overdracht');
    });
  });
}
