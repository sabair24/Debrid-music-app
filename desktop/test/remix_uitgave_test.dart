// Remixuitgaven tussen de albums (Saber, 20-10-2026: "dit staat ook vaak tussen albums ?? remixen
// enzo", bij Madonna). De nummers hieronder zijn echt, uit Deezers /album/{id} van 20-10-2026.
import 'dart:io';

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/discography.dart';
import 'package:flutter_test/flutter_test.dart';

const _deeperAndDeeper = [
  'Deeper and Deeper (Album Edit)',
  "Deeper and Deeper (Shep's Deep Makeover Mix)",
  "Deeper and Deeper (David's Klub Mix)",
  'Deeper and Deeper (Shep\'s Classic 12")',
  "Deeper and Deeper (Shep's Fierce Deeper Dub)",
  "Deeper and Deeper (David's Love Dub)",
  "Deeper and Deeper (Shep's Deepstrumental)",
  "Deeper and Deeper (David's Deeper Dub)",
  "Deeper and Deeper (Shep's Deeper Dub)",
  "Deeper and Deeper (Shep's Deep Bass Dub)",
  "Deeper and Deeper (Shep's Deep Beats)",
  'Deeper and Deeper (Album Instrumental)',
];
const _rain = [
  'Rain (Radio Remix)',
  'Waiting (Remix)',
  'Rain (Radio Remix Edit)',
  'Up Down Suite',
  'Rain (Video Edit)',
  'Fever (Edit Two)',
];
const _handOnYourHeart = [
  'Hand On Your Heart',
  'Hand on Your Heart',
  'Hand on Your Heart',
  'Hand on Your Heart',
  'Hand on Your Heart',
  'Hand on Your Heart',
  'Just Wanna Love You',
  'Just Wanna Love You',
];
const _neverTooLate = [
  'Never Too Late',
  'Never Too Late (Exnteded Version)',
  'Never Too Late (Instrumental)',
  'Never Too Late (Backing Track)',
  'Never Too Late (Oz Tour Mix)',
  "I'm Over Dreaming (Over You) (Instrumental)",
  "I'm Over Dreaming (Over You) (Backing Track)",
  "Kylie's Smiley Mix",
];
const _locoMotionAustralisch = [
  'Locomotion',
  'Locomotion (Chugga-Motion Mix)',
  'Locomotion (The Girl Meets Boy Mix)',
  'Getting Closer',
  'Getting Closer (UK Mix)',
  'Getting Closer (UK Instrumental)',
  'Getting Closer (Extended Oz Mix)',
  'Getting Closer (Extended Oz Instrumental)',
  'Glad to Be Alive',
];
const _bedtimeStories = [
  'Survival', 'Secret', "I'd Rather Be Your Lover", "Don't Stop", 'Inside of Me', 'Human Nature',
  'Forbidden Love', 'Love Tried to Welcome Me', 'Sanctuary', 'Bedtime Story', 'Take a Bow',
];
final _vijftigNummerEen = [
  'Holiday (7" Version) (2022 Remaster)',
  'Like A Virgin (7" Version) (2022 Remaster)',
  'Material Girl (7" Version) (2022 Remaster)',
  'Into The Groove (You Can Dance Remix Edit) (2022 Remaster)',
  'Open Your Heart (Video Version) (2022 Remaster)',
  'Physical Attraction (You Can Dance Remix Edit) (2022 Remaster)',
  'Everybody (You Can Dance Remix Edit) (2022 Remaster)',
  'Like A Prayer (7" Remix Edit) (2022 Remaster)',
];

void main() {
  group('maxisingle', () {
    test('DE KERN: de gemeten maxisingles', () {
      expect(isMaxisingle('Deeper and Deeper', _deeperAndDeeper), isTrue);
      expect(isMaxisingle('Rain', _rain), isTrue, reason: 'met B-kanten');
      expect(isMaxisingle('Hand on Your Heart', _handOnYourHeart), isTrue, reason: 'zonder versienamen');
      expect(isMaxisingle('Never Too Late', _neverTooLate), isTrue);
      expect(isMaxisingle('The Loco-Motion (Australian Version)', _locoMotionAustralisch), isTrue,
          reason: 'de nummers heten "Locomotion": zonder lidwoord en zonder streepje');
    });

    test('een gewoon album niet, ook niet met een reprise van het titelnummer', () {
      expect(isMaxisingle('Bedtime Stories', _bedtimeStories), isFalse);
      expect(isMaxisingle('Ray of Light', ['Drowned World', 'Swim', 'Ray of Light', 'Candy Perfume Girl',
          'Skin', 'Nothing Really Matters', 'Sky Fits Heaven', 'Shanti', 'Frozen', 'The Power of Good-Bye',
          'To Have and Not to Hold', 'Little Star', 'Mer Girl', 'Ray of Light (Reprise)']), isFalse);
    });

    test('meer dan vijftien nummers is geen single', () {
      expect(isMaxisingle('X', [for (var i = 0; i < 16; i++) 'X (Mix $i)']), isFalse);
    });
  });

  group('remixalbum', () {
    test('vijftig remixen van verschillende nummers', () {
      expect(isRemixAlbum(_vijftigNummerEen), isTrue, reason: 'twee staarten: "(7" Version) (2022 Remaster)"');
    });

    test('een deluxe-album met een schijf remixen erachter niet (40 % versies)', () {
      expect(
          isRemixAlbum([
            ..._bedtimeStories,
            'Bonus Track',
            for (var i = 0; i < 8; i++) '${_bedtimeStories[i]} (Remix $i)',
          ]),
          isFalse);
    });

    test('een geremasterd album niet: dezelfde opname is geen versie', () {
      expect(isRemixAlbum([for (final t in _bedtimeStories) '$t (2022 Remaster)']), isFalse);
    });
  });

  group('op de titel', () {
    test('albums en ep\'s met "remix" of "mix" in de titel zijn remixen', () {
      for (final t in ['Hollywood (Remixes)', 'American Life (The Remixes)', 'Remixed & Revisited', 'X-Ray Mixes',
          'Music Mix 2001 Part 4', 'You Can Dance (Single Edits of Album Remixes)']) {
        expect(soortMetTitel(RecordKind.album, t), RecordKind.remix, reason: t);
      }
      expect(soortMetTitel(RecordKind.ep, 'Frozen (Remixes)'), RecordKind.remix);
    });

    test('live op de titel, in het Engels en het Frans', () {
      for (final t in ['Live In New York', 'Live In Dublin', 'Greatest Hits Live', 'Une Seule Fois / Live 2013',
          'La tournée mondiale Taking Chances (Le spectacle Live à Montréal)', ' Live - London Festival EP',
          'Live 2010 (Fri December 10th NIA Birmingham)']) {
        expect(soortMetTitel(RecordKind.album, t), RecordKind.live, reason: t);
      }
      for (final t in ['Live Your Life', 'Live to Tell', 'Alive']) {
        expect(soortMetTitel(RecordKind.album, t), RecordKind.album, reason: t);
      }
    });

    test('verzamelaars op de titel, maar niet "Golden"', () {
      for (final t in ['Kylie Hits', 'Greatest Hits', 'Anthology: The Best Of Michael Jackson', 'The Essential Michael Jackson',
          'Finally Enough Love: 50 Number Ones']) {
        expect(soortMetTitel(RecordKind.album, t), RecordKind.compilation, reason: t);
      }
      expect(soortMetTitel(RecordKind.album, 'Golden'), RecordKind.album);
    });

    test('een remixsingle blijft een single, en een gewoon album een album', () {
      expect(soortMetTitel(RecordKind.single, 'Danceteria (Harry Romero Remix)'), RecordKind.single);
      expect(soortMetTitel(RecordKind.album, 'Mixed Emotions'), RecordKind.album);
      expect(soortMetTitel(RecordKind.album, 'Bedtime Stories'), RecordKind.album);
    });
  });

  group('aangesloten', () {
    String bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

    test('Deezer bladert door voorbij honderd (Madonna: 147)', () {
      expect(bron('lib/catalog.dart'), contains("'\$_base/artist/\$artistId/albums?limit=100&index=\$index'"));
    });

    test('geen bootlegs: Discogs met "Unofficial" in het formaat, MusicBrainz zoals de website', () {
      final dg = bron('lib/discogs.dart');
      expect(dg, contains('        if (noemtOnofficieel(formaat)) continue;\n'));
      expect(dg, contains('        if (noemtOnofficieel(sweep.formaatPerMaster[e.key])) continue;\n'));
      expect(bron('lib/musicbrainz.dart'), contains('&release-group-status=website-default'));
    });

    test('de titelregel staat vóór het samenvoegen, en het nakijken gaat naar schijf', () {
      expect(bron('lib/discography.dart'), contains('      final soort = soortMetTitel(r0.kind, r0.title);\n'));
      expect(bron('lib/main.dart'),
          contains('if (!_gasten.contains(r.key)) metNagekekenSoort(r, singles: _maxisingles, remixen: _remixAlbums),'));
      expect(bron('lib/discography_service.dart'), contains("static const schema = 'disco|v11';"));
      expect(bron('lib/main.dart'),
          contains('volgensMusicBrainz(mergeDiscography([dz.releases, mb.releases, dg.releases]), mb.releases,\n'
              '            artiest: naam),'));
    });
  });

  group('samenvoegen', () {
    DiscoRelease dz(String t, RecordKind k, int id) => DiscoRelease(
        title: t, kind: k, firstDate: '2025-11-28', sources: const {DiscoSource.deezer},
        refs: {DiscoSource.deezer: CatalogRef.deezer(id)});
    DiscoRelease mb(String t, RecordKind k) => DiscoRelease(
        title: t, kind: k, firstDate: '2025-11-28', sources: const {DiscoSource.musicbrainz},
        refs: {DiscoSource.musicbrainz: CatalogRef.musicbrainzGroup('mb-$t')});

    test('alleen Deezer zegt "album", MusicBrainz zegt EP: één plaat, een EP', () {
      final uit = mergeDiscography([
        [dz('Bedtime Stories – The Untold Chapter', RecordKind.album, 856219632)],
        [mb('Bedtime Stories: The Untold Chapter', RecordKind.ep)],
      ]);
      expect(uit, hasLength(1));
      expect(uit.single.kind, RecordKind.ep);
      expect(uit.single.refs[DiscoSource.deezer]!.intId, 856219632, reason: 'de Deezer-link blijft');
    });

    test('maar niet als MusicBrainz het album zelf ook kent', () {
      final uit = mergeDiscography([
        [dz('Funhouse', RecordKind.album, 1)],
        [mb('Funhouse', RecordKind.album), mb('Funhouse', RecordKind.single)],
      ]);
      expect(uit.where((r) => r.kind == RecordKind.album), hasLength(1));
    });

    test('de titelregel werkt al vóór het samenvoegen', () {
      final uit = mergeDiscography([
        [dz('Hollywood (Remixes)', RecordKind.album, 463923855)],
      ]);
      expect(uit.single.blok, RecordKind.remix);
    });

    test('nagekeken: een maxisingle naar de singles, een remixalbum naar de remixen', () {
      final a = dz('Deeper and Deeper', RecordKind.album, 369850057);
      final b = dz('Finally Enough Love: 50 Number Ones', RecordKind.album, 343865387);
      final c = dz('Bedtime Stories', RecordKind.album, 90986);
      final uit = [for (final r in [a, b, c]) metNagekekenSoort(r, singles: {369850057}, remixen: {343865387})];
      expect(uit.map((r) => r.kind), [RecordKind.single, RecordKind.remix, RecordKind.album]);
    });
  });
}
