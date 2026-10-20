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
    expect(main.contains('    return _slskPerTitel.putIfAbsent(\n'), isTrue,
        reason: 'de telling naast elke rij zeeft niet bij elke opbouw opnieuw');
    expect(main.contains('    if (!identical(_slskPerTitelVan, _albumSlsk)) {'), isTrue,
        reason: 'een nieuw zoekresultaat begint het geheugen opnieuw');
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
}
