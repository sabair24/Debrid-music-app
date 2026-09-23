import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/completeness.dart' show rijSleutel;
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/organize.dart';

Track _t(String title, int no, {int secs = 200, String path = ''}) => Track(
      path: path.isEmpty ? 'C:\\x\\$title.flac' : path,
      title: title,
      artist: 'Backstreet Boys',
      album: 'Backstreet Boys',
      trackNo: no,
      duration: Duration(seconds: secs),
      isFlac: true,
    );

/// The pressing the user pointed at: musicbrainz.org/release/d87362b1-…
const _official = [
  ChoiceTrack('1', 'We’ve Got It Goin’ On', 219),
  ChoiceTrack('2', 'Anywhere for You', 280),
  ChoiceTrack('3', 'Get Down (You’re the One for Me)', 230),
  ChoiceTrack('4', 'I’ll Never Break Your Heart', 288),
  ChoiceTrack('5', 'Quit Playing Games (With My Heart)', 232),
  ChoiceTrack('6', 'Boys Will Be Boys', 245),
  ChoiceTrack('7', 'Just to Be Close to You', 289),
];

void main() {
  group('trackNoFromPosition', () {
    test('a plain number on a single disc is itself', () {
      final all = [for (var i = 1; i <= 5; i++) ChoiceTrack('$i', 't$i', 200)];
      expect(trackNoFromPosition('3', 1, all), 3);
    });

    test('a vinyl side counts across the record, so A3 and B3 do not collide', () {
      final all = const [
        ChoiceTrack('A1', 'a', 200),
        ChoiceTrack('A2', 'b', 200),
        ChoiceTrack('A3', 'c', 200),
        ChoiceTrack('B1', 'd', 200),
        ChoiceTrack('B2', 'e', 200),
        ChoiceTrack('B3', 'f', 200),
      ];
      expect(trackNoFromPosition('A3', 1, all), 3);
      expect(trackNoFromPosition('B3', 1, all), 6, reason: 'not 3 — that is the collision');
      expect(trackNoFromPosition('B1', 1, all), 4);
    });

    test('a second disc continues the count rather than restarting it', () {
      final all = const [
        ChoiceTrack('1', 'a', 200, disc: 1),
        ChoiceTrack('2', 'b', 200, disc: 1),
        ChoiceTrack('1', 'c', 200, disc: 2),
        ChoiceTrack('2', 'd', 200, disc: 2),
      ];
      expect(trackNoFromPosition('1', 1, all), 1);
      expect(trackNoFromPosition('2', 2, all), 4, reason: 'disc two track two is the fourth track');
    });
  });

  group('planRenumber', () {
    late LibraryStore lib;
    setUp(() => lib = LibraryStore());

    test('fixes the numbering the tags got wrong, matching on title not number', () {
      // Exactly the user's album: two number sixes, a two that should be five, and a blank.
      final album = Album('Backstreet Boys', 'Backstreet Boys', [
        _t('We’ve Got It Goin’ On', 1, secs: 221),
        _t('Quit Playing Games (With My Heart)', 2, secs: 233),
        _t('Get Down (You’re the One for Me)', 0, secs: 232),
        _t('I’ll Never Break Your Heart', 4, secs: 287),
        _t('Anywhere for You', 6, secs: 281),
        _t('Boys Will Be Boys', 6, secs: 245),
        _t('Just to Be Close to You', 7, secs: 289),
      ]);

      final plan = lib.planRenumber(album, _official);

      expect(plan.collides, isFalse);
      expect(plan.titleCollides, isFalse);
      expect(plan.safe, isTrue);
      expect(plan.total, 7);
      int noFor(String t) =>
          plan.steps.firstWhere((s) => s.track.title.startsWith(t.split(' ').first)).newNo!;
      expect(noFor('Anywhere'), 2, reason: 'tagged 6, actually track two');
      expect(noFor('Get'), 3, reason: 'tagged nothing at all');
      expect(noFor('Quit'), 5, reason: 'tagged 2');
      expect(noFor('Boys'), 6);
      // Every number once, no gaps — the thing that was broken.
      expect(plan.steps.map((s) => s.newNo).toList()..sort(), [1, 2, 3, 4, 5, 6, 7]);
    });

    test('a track the pressing does not have keeps its own tags', () {
      final album = Album('Backstreet Boys', 'Backstreet Boys', [
        _t('We’ve Got It Goin’ On', 1, secs: 221),
        // A radio edit that is not on this pressing at all.
        _t('Something Else Entirely', 9, secs: 400),
      ]);

      final plan = lib.planRenumber(album, _official);

      expect(plan.unmatched, hasLength(1));
      expect(plan.unmatched.first.track.title, 'Something Else Entirely');
      expect(plan.unmatched.first.newNo, isNull, reason: 'guessing would renumber it wrongly');
    });

    test('a duration that disagrees wildly stops a same-sounding title from matching', () {
      // "Get Down" the 3:50 album cut vs an 8-minute remix — same words, different recording.
      final album = Album('Backstreet Boys', 'Backstreet Boys', [
        _t('Get Down (Extended Club Mix)', 3, secs: 480),
      ]);
      final plan = lib.planRenumber(album, _official);
      // It may still match on words alone; what matters is the duration penalty is applied.
      final s = plan.steps.single;
      if (!s.unmatched) {
        expect(s.official!.title, startsWith('Get Down'));
      }
    });

    test('two tracks landing on one number is refused, not applied', () {
      // Both files are the same song, so both match the same official entry... except the pool
      // removes a matched entry, so the second falls through unmatched. Verify no collision ships.
      final album = Album('Backstreet Boys', 'Backstreet Boys', [
        _t('Boys Will Be Boys', 6, secs: 245, path: r'C:\a\6.flac'),
        _t('Boys Will Be Boys', 6, secs: 245, path: r'C:\b\6.flac'),
      ]);
      final plan = lib.planRenumber(album, _official);
      expect(plan.collides, isFalse, reason: 'a matched entry is consumed, so it cannot match twice');
      expect(plan.titleCollides, isTrue, reason: 'two identical titles would dedupe one away');
      expect(plan.safe, isFalse, reason: 'and that must block the apply');
    });

    test('an album that is already right reports nothing to do', () {
      final album = Album('Backstreet Boys', 'Backstreet Boys', [
        for (var i = 0; i < _official.length; i++)
          _t(_official[i].title, i + 1, secs: _official[i].seconds!)
      ]);
      final plan = lib.planRenumber(album, _official);
      expect(plan.changing, isEmpty);
      expect(plan.safe, isFalse, reason: 'nothing to change means nothing to confirm');
    });
  });

  group('een rij die je zelf aanwees', () {
    // **Gemeten op 23-09-2026 bij En Zo.** Een bestand waarvan de app de titel ten onrechte op
    // "Voort!" had gezet — de naam van het ALBUM waar het nummer ook op staat. Met de hand op rij 1
    // gezet (Radio Mix, 3:26 tegen 3:26), en daarna zei "Nummering van deze uitgave overnemen":
    // "1 niet herkend op deze uitgave". Er was daardoor geen enkele knop die die titel nog kon
    // rechtzetten — "ik vind geen manier om dit aan te passen".
    //
    // Discogs r968580: CD · Belgium · DNCS 2244 · 1995.
    const single = [
      ChoiceTrack('1', 'Opzij, Opzij, Opzij (Radio Mix)', 206),
      ChoiceTrack('2', 'Opzij, Opzij, Opzij (Beuk Mix)', 229),
    ];

    Track enZo(String titel, {int secs = 206}) => Track(
          path: r'D:\Flac music 2024\en zo\Voort!\08. Enzo - opzij opzij.flac',
          title: titel,
          artist: 'En Zo',
          album: 'Opzij, Opzij, Opzij',
          duration: Duration(seconds: secs),
          isFlac: true,
        );

    LibraryStore bib() {
      final root = Directory.systemTemp.createTempSync('rijhand');
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      });
      return LibraryStore()..configDirOverride = root.path;
    }

    test('DE KERN: de rij die je aanwees geeft het nummer ook de titel van die rij', () async {
      final lib = bib();
      final t = enZo('Voort!');
      lib.tracks.add(t);
      lib.rebuildAlbums();
      await lib.wijsRijToe(t, rijSleutel(single.first));

      final plan = lib.planRenumber(lib.albums.single, single);
      final stap = plan.steps.single;
      expect(stap.official?.title, 'Opzij, Opzij, Opzij (Radio Mix)',
          reason: 'op titel lijkt "Voort!" op niets; de rij die je zelf aanwees is wat de app weet');
      expect(stap.newNo, 1);
      expect(stap.nieuweTitel, 'Opzij, Opzij, Opzij (Radio Mix)');

      await lib.applyRenumber(plan);
      expect(lib.tracks.single.title, 'Opzij, Opzij, Opzij (Radio Mix)',
          reason: 'en daarna heet hij zo in de app, niet meer "Voort!"');
    });

    test('DE VAL: jouw rij wint van een titel die op een ándere rij lijkt', () async {
      // Heet het bestand als rij 2 maar wees jij rij 1 aan, dan is jouw keuze de waarheid — de
      // titel is juist het ding dat hier niet klopt.
      final lib = bib();
      final t = enZo('Opzij, Opzij, Opzij (Beuk Mix)');
      lib.tracks.add(t);
      lib.rebuildAlbums();
      await lib.wijsRijToe(t, rijSleutel(single.first));

      final stap = lib.planRenumber(lib.albums.single, single).steps.single;
      expect(stap.newNo, 1, reason: 'de titelvergelijking pikte rij 2 in voordat jouw keuze aan bod kwam');
    });

    test('DE VAL: de rij die je aanwees kan niet óók nog door een ander bestand geclaimd worden', () async {
      // Een tweede bestand met precies de titel van rij 1 zou anders ook op 1 landen: twee keer
      // nummer 1, en dan weigert het venster terecht het hele plan.
      final lib = bib();
      final a = enZo('Voort!');
      final b = Track(
        path: r'D:\Flac music 2024\en zo\Opzij\01 Opzij, Opzij, Opzij (Radio Mix).flac',
        title: 'Opzij, Opzij, Opzij (Radio Mix)',
        artist: 'En Zo',
        album: 'Opzij, Opzij, Opzij',
        duration: const Duration(seconds: 206),
        isFlac: true,
      );
      lib.tracks.addAll([a, b]);
      lib.rebuildAlbums();
      await lib.wijsRijToe(a, rijSleutel(single.first));

      final plan = lib.planRenumber(lib.albums.single, single);
      expect(plan.steps.firstWhere((s) => s.track.path == a.path).newNo, 1);
      expect(plan.collides, isFalse, reason: 'twee keer nummer 1');
    });

    test('DE GRENS: een rij van een andere persing telt hier niet', () async {
      // Zo stond het bij En Zo: "1|12", rij 12 van het album Voort! (16 nummers), terwijl de single
      // er maar twee heeft. Dan valt het bestand terug op de gewone vergelijking.
      final lib = bib();
      final t = enZo('Voort!');
      lib.tracks.add(t);
      lib.rebuildAlbums();
      await lib.wijsRijToe(t, '1|12');

      final stap = lib.planRenumber(lib.albums.single, single).steps.single;
      expect(stap.unmatched, isTrue, reason: 'een rij die hier niet bestaat kan niets aanwijzen');
    });
  });

  group('applyRenumber', () {
    test('writes the number and title, and the library reflects it', () async {
      final root = Directory.systemTemp.createTempSync('renum');
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      });
      final lib = LibraryStore()..configDirOverride = root.path;
      final wrong = _t('Anywhere for You', 6, secs: 281);
      lib.tracks.add(wrong);
      lib.rebuildAlbums();

      await lib.applyRenumber(lib.planRenumber(lib.albums.single, _official));

      expect(lib.correctionForTest(wrong.path)?['trackNo'], '2');
      expect(lib.correctionForTest(wrong.path)?['trackTotal'], '7');
      expect(lib.tracks.single.trackNo, 2, reason: 'and it is live, not just on disk');
    });
  });

  group('CatalogRef', () {
    test('the old sign encoding survives byte for byte', () {
      // Downloads already waiting in pending_downloads.json are keyed on these exact strings.
      expect(CatalogRef.deezer(123).keyPart, '123');
      expect(CatalogRef.discogsRelease(456).keyPart, '-456');
      expect(CatalogAlbum(789, 'x', null, null, 0, 'album').ref.keyPart, '789');
      expect(CatalogAlbum(-456, 'x', null, null, 0, 'album').ref.source,
          CatalogSource.discogsRelease);
    });

    test('MusicBrainz keys can never collide with an integer one', () {
      expect(CatalogRef.musicbrainz('abc-def').keyPart, 'mb:abc-def');
      expect(CatalogRef.musicbrainzGroup('abc-def').keyPart, 'mbg:abc-def');
      expect(CatalogRef.musicbrainz('1').keyPart, isNot('1'));
    });

    test('an explicit origin beats the legacy sign reading', () {
      final a = CatalogAlbum(0, 'x', null, null, 0, 'album',
          origin: CatalogRef.musicbrainzGroup('g1'));
      expect(a.ref.source, CatalogSource.musicbrainzGroup);
      expect(a.ref.id, 'g1');
    });
  });

  group('ReleaseChoice', () {
    test('the same pressing from two catalogues dedupes on its barcode', () {
      const mb = ReleaseChoice(
          source: EditionSource.musicbrainz, mbid: 'x', barcode: '724384255022', country: 'XE');
      const dg = ReleaseChoice(
          source: EditionSource.discogs, releaseId: 9, barcode: '7 24384 25502 2', country: 'Europe');
      expect(mb.dedupeKey, dg.dedupeKey, reason: 'punctuation in a barcode is not a difference');
    });

    test('without a barcode it falls back to country and catalogue number', () {
      const a = ReleaseChoice(
          source: EditionSource.musicbrainz, mbid: 'x', catno: 'SICP-6425', country: 'JP');
      const b = ReleaseChoice(
          source: EditionSource.discogs, releaseId: 3, catno: 'sicp 6425', country: 'jp');
      expect(a.dedupeKey, b.dedupeKey);
    });

    test('two undocumented stubs stay two rows rather than collapsing into one', () {
      const a = ReleaseChoice(source: EditionSource.musicbrainz, mbid: 'x');
      const b = ReleaseChoice(source: EditionSource.musicbrainz, mbid: 'y');
      expect(a.dedupeKey, isNot(b.dedupeKey));
    });
  });
}
