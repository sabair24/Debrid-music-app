/// "Staat ook op…" (23-10-2026): één regel per plaat, de platen die je hebt bovenaan met een vinkje, en een tik geeft
/// de keuze.
///
/// Saber, met een schermafdruk van "We Don't Talk Anymore (feat. Selena Gomez)": *"staat ook op, laadt geen hoes, en kan
/// nie op klikken"*. Er stond één plaat, "Nine Track Mind (Special Edition)". Zijn keuzes daarna: een keuzemenu bij een
/// tik; studioalbums, singles en ep's, en verzamelaars; één regel per plaat; wat je hebt bovenaan met een vinkje.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/metadata.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Map<String, dynamic> _persing(String id, String titel, String groep, String soort, String datum,
        {List<String> ook = const [], String artiest = 'Charlie Puth'}) =>
    {
      'id': id,
      'title': titel,
      'status': 'Official',
      'date': datum,
      'artist-credit': [
        {'name': artiest}
      ],
      'release-group': {'id': groep, 'primary-type': soort, 'secondary-types': ook},
    };

MbRecording _opname(String titel, List<Map<String, dynamic>> persingen, {String artiest = 'Charlie Puth'}) =>
    MbRecording.from({
      'id': 'rec-$titel-$artiest-${persingen.length}',
      'title': titel,
      'artist-credit': [
        {'name': artiest, 'artist': {'id': 'cp'}}
      ],
      'releases': persingen,
    });

// Zoals MusicBrainz het gaf bij de controle van 23-10-2026, plus wat er niet bij hoort.
final _opnames = [
  _opname("We Don't Talk Anymore", [
    _persing('r1', 'Nine Track Mind', 'g-ntm', 'Album', '2016-01-29'),
    _persing('r2', 'Nine Track Mind (Deluxe)', 'g-ntm', 'Album', '2016-01-29'),
    _persing('r3', 'Nine Track Mind (Special Edition)', 'g-ntm-se', 'Album', '2015-11-06'),
    _persing('r4', "We Don't Talk Anymore", 'g-s', 'Single', '2016-05-24'),
    _persing('r5', "We Don't Talk Anymore (f. Selena Gomez)", 'g-s', 'Single', '2016-05-24'),
    _persing('r6', "We Don't Talk Anymore (Music Video)", 'g-s', 'Single', '2016-06-01'),
    _persing('r7', 'Now 95', 'g-now', 'Album', '2016-11-18', ook: ['Compilation'], artiest: 'Various Artists'),
    _persing('r8', 'Live at the Ryman', 'g-live', 'Album', '2017', ook: ['Live']),
    _persing('r9', 'The Wall Soundtrack', 'g-st', 'Album', '2016', ook: ['Soundtrack']),
  ]),
  // Een cover door een andere band: hoort er niet bij.
  _opname("We Don't Talk Anymore", [_persing('r10', 'Covers 2016', 'g-cov', 'Album', '2016')],
      artiest: 'Charlie Puth Tribute Band'),
];

/// Een kleine maar geldige FLAC met [commentaar] — zoals in flac_write_test.
Uint8List _flac(List<String> commentaar) {
  final out = BytesBuilder()..add(ascii.encode('fLaC'));
  void blok(int soort, List<int> lijf, bool laatste) {
    out.add([(laatste ? 0x80 : 0) | soort, (lijf.length >> 16) & 0xFF, (lijf.length >> 8) & 0xFF, lijf.length & 0xFF]);
    out.add(lijf);
  }

  final si = Uint8List(34);
  si[10] = (44100 >> 12) & 0xFF;
  si[11] = (44100 >> 4) & 0xFF;
  si[12] = ((44100 & 0x0F) << 4) | (1 << 1);
  si[14] = 0x02;
  blok(0, si, false);
  final b = BytesBuilder();
  void u32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  final ven = utf8.encode('reference libFLAC 1.3.2');
  u32(ven.length);
  b.add(ven);
  u32(commentaar.length);
  for (final c in commentaar) {
    final e = utf8.encode(c);
    u32(e.length);
    b.add(e);
  }
  blok(4, b.toBytes(), false);
  blok(1, List.filled(64, 0), true);
  out.add(List.filled(4096, 0x7F));
  return out.toBytes();
}

/// De timers van de bibliotheek en het menu laten uitlopen, zodat de toets niets laat hangen.
Future<void> _uitlopen(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(minutes: 1));
}

void main() {
  group('de platen', () {
    test('DE KERN: met gast in de titel, één regel per plaat, de edities erachter, het jaar van het origineel', () {
      final r = platenVoorStaatOokOp(_opnames,
          artiest: 'Charlie Puth',
          titel: "We Don't Talk Anymore (feat. Selena Gomez)",
          groepen: const {
            'g-ntm': (titel: 'Nine Track Mind', datum: '2016-01-29'),
            'g-ntm-se': (titel: 'Nine Track Mind (Special Edition)', datum: '2015-11-06'),
          });
      expect([for (final p in r) '$p'], [
        'Nine Track Mind (Studioalbum, 2016; ook Special Edition, Deluxe)',
        "We Don't Talk Anymore (Single, 2016; ook Music Video)",
        'Now 95 (Verzamelaar, 2016)',
      ], reason: 'geen live-plaat, geen soundtrack, geen cover; de Special Edition (2015) zet het jaar niet');
      expect(r.first.uitgave, 'r1', reason: 'vastgezet op het origineel');
      expect(r.first.hoes(), 'https://coverartarchive.org/release-group/g-ntm/front-250',
          reason: 'de hoes van de plaat, die heeft het archief vaker dan die van één persing');
      expect(r[2].artiest, 'Various Artists');
    });

    test('hetzelfde nummer, met of zonder gast en editie', () {
      expect(zelfdeNummer("We Don't Talk Anymore (feat. Selena Gomez)", "We Don't Talk Anymore"), isTrue);
      expect(zelfdeNummer('Nothing Compares 2 U (2009 Remaster)', 'Nothing Compares 2 U'), isTrue);
      expect(zelfdeNummer("We Don't Talk Anymore (Live)", "We Don't Talk Anymore"), isFalse);
      expect(zelfdeNummer('Attention', "We Don't Talk Anymore"), isFalse);
    });
  });

  group('de albumtag van de uploader (Saber: "Ja als het 100 procent klopt ja")', () {
    late Directory map;
    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_uploader_');
      setAppDirForTest(map.path);
    });
    tearDown(() {
      DownloadManager.albumVanUploader = null;
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('DE KERN: klopt hij, dan blijft hij — met de naam en het jaar van MusicBrainz; anders gaat hij weg', () async {
      final f = File('${map.path}${Platform.pathSeparator}Lovefool.flac')
        ..writeAsBytesSync(_flac(['TITLE=Lovefool', 'ARTIST=The Cardigans', 'ALBUM=First Band On the Moon', 'DATE=2005']));
      final gevraagd = <String>[];
      DownloadManager.albumVanUploader = (a, t, album) async {
        gevraagd.add('$a|$t|$album');
        return album == 'First Band On the Moon' ? (album: 'First Band on the Moon', jaar: 1996) : null;
      };
      final cfg = AppSettings();
      final d = DownloadManager(OnlineService(cfg), SoulseekService(cfg), map.path, () async {});
      final zonder = DownloadManager.gezagVoorHaal(artiest: 'The Cardigans', titel: 'Lovefool', jaar: 1997, seconden: 194);
      final g = await d.metAlbumVanUploader(zonder, f.path, 'The Cardigans', 'Lovefool', 1997, 194);
      expect(gevraagd, ['The Cardigans|Lovefool|First Band On the Moon']);
      expect((g.album, g.year), ('First Band on the Moon', 1996), reason: 'het vroegste jaar: de plaat, niet 1997');

      // Niet zeker: dan blijft het gezag zonder album, en gaat de tag weg zoals voorheen.
      DownloadManager.albumVanUploader = (a, t, album) async => null;
      expect((await d.metAlbumVanUploader(zonder, f.path, 'The Cardigans', 'Lovefool', 1997, 194)).album, '');

      // Wist het opzoeken het al, dan wordt er niets nagekeken.
      gevraagd.clear();
      DownloadManager.albumVanUploader = (a, t, album) async {
        gevraagd.add(album);
        return null;
      };
      final met = DownloadManager.gezagVoorHaal(artiest: 'The Cardigans', titel: 'Lovefool', album: 'Gran Turismo', jaar: 1998);
      expect((await d.metAlbumVanUploader(met, f.path, 'The Cardigans', 'Lovefool', 1998, 194)).album, 'Gran Turismo');
      expect(gevraagd, isEmpty);
    });

    test('beide radiowegen kijken het na, en de pc zet de controle aan', () {
      final bron = File('lib/online.dart').readAsStringSync();
      expect(RegExp(r'gezag = await metAlbumVanUploader\(gezag, uit\.path, artiest, titel, jaar, seconden\);')
          .allMatches(bron)
          .length, 2, reason: 'Soulseek en TIDAL');
      expect(File('lib/main.dart').readAsStringSync(), contains('DownloadManager.albumVanUploader = uploaderAlbumKlopt;'));
    });
  });

  group('het blad', () {
    late Directory map;
    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_staatookop_');
      setAppDirForTest(map.path);
    });
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    const platen = [
      Plaatregel(titel: "We Don't Talk Anymore", soort: 'Single', jaar: 2016, groep: 'g-s', uitgave: 'r4'),
      Plaatregel(
          titel: 'Nine Track Mind',
          soort: 'Studioalbum',
          jaar: 2016,
          groep: 'g-ntm',
          uitgave: 'r1',
          edities: ['Deluxe', 'Special Edition']),
      Plaatregel(titel: 'Now 95', soort: 'Verzamelaar', jaar: 2016, groep: 'g-now', uitgave: 'r7', artiest: 'Various Artists'),
    ];
    final nummer = Track(
        path: '/m/Charlie Puth/Nine Track Mind/05.flac',
        title: "We Don't Talk Anymore (feat. Selena Gomez)",
        artist: 'Charlie Puth',
        album: 'Nine Track Mind');

    Future<List<String>> blad(WidgetTester t, double breed) async {
      t.view.physicalSize = Size(breed, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final lib = LibraryStore();
      // De plaat waarop het nummer al staat, in je bibliotheek.
      lib.tracks.add(nummer);
      lib.rebuildAlbums();
      final gevraagd = <String>[];
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
          ChangeNotifierProvider<LibraryStore>.value(value: lib),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StaatOokOpBlad(
                track: nummer,
                zoek: (a, ti) async {
                  gevraagd.add('$a|$ti');
                  return platen;
                }),
          ),
        ),
      ));
      await t.pumpAndSettle();
      return gevraagd;
    }

    for (final breed in [360.0, 1920.0]) {
      testWidgets('DE KERN op $breed punten: wat je hebt bovenaan met een vinkje, en een tik geeft de keuze', (t) async {
        final gevraagd = await blad(t, breed);
        expect(gevraagd, ["Charlie Puth|We Don't Talk Anymore (feat. Selena Gomez)"]);
        final ntm = t.getRect(find.text('Nine Track Mind'));
        final single = t.getRect(find.text("We Don't Talk Anymore"));
        expect(ntm.top, lessThan(single.top), reason: 'de plaat die je hebt eerst, ook al kwam de single eerst binnen');
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
        expect(find.textContaining('In je bibliotheek'), findsOneWidget);
        expect(find.textContaining('ook als Deluxe, Special Edition'), findsOneWidget);
        expect(t.widget<Text>(find.text('Nine Track Mind')).maxLines, 2, reason: 'een lange naam breekt, maar blijft leesbaar');
        expect(t.takeException(), isNull);

        await t.tap(find.text("We Don't Talk Anymore"));
        await t.pumpAndSettle();
        expect(find.text('Album online bekijken'), findsOneWidget);
        expect(find.text('Dit nummer op deze plaat zetten'), findsOneWidget);
        expect(find.text('Plaat ophalen'), findsOneWidget);
        await _uitlopen(t);
      });
    }

    testWidgets('bij een plaat die je hebt: openen, en geen "ophalen"', (t) async {
      await blad(t, 411);
      await t.tap(find.text('Nine Track Mind'));
      await t.pumpAndSettle();
      expect(find.text('Album openen'), findsOneWidget);
      expect(find.text('Plaat ophalen'), findsNothing);
      await _uitlopen(t);
    });
  });
}
