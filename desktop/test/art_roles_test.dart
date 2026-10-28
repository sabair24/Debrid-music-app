import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/library.dart';

/// Saying which scan is the sleeve, which is the back, and which is the disc.
///
/// Discogs marks one image "primary" and calls the rest "secondary" — it never states what a
/// picture SHOWS, so the app infers it from shape and pixels and is sometimes wrong. This is the
/// user's answer, and it has to outlive a rescan and never be quietly overruled.
void main() {
  late Directory root;
  late LibraryStore lib;
  setUp(() {
    root = Directory.systemTemp.createTempSync('roles');
    lib = LibraryStore()..configDirOverride = '${root.path}${Platform.pathSeparator}_cfg';
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('nothing assigned means the guesses stand', () {
    expect(lib.albumArtRoles('Daft Punk', 'Random Access Memories'), isEmpty);
  });

  test('an assignment is remembered, and survives a fresh store', () async {
    await lib.setAlbumArtRole('Daft Punk', 'Random Access Memories', 'back', 'http://x/back.jpg');
    expect(lib.albumArtRoles('Daft Punk', 'Random Access Memories'),
        {'back': 'http://x/back.jpg'});

    // A second store over the same config dir — what a restart amounts to.
    final again = LibraryStore()..configDirOverride = lib.configDirOverride;
    await again.loadAlbumArtRoles();
    expect(again.albumArtRoles('Daft Punk', 'Random Access Memories'),
        {'back': 'http://x/back.jpg'});
  });

  test('the key ignores punctuation and case, as the album grouping does', () async {
    await lib.setAlbumArtRole('Daft Punk', 'Random Access Memories', 'disc', 'http://x/cd.jpg');
    expect(lib.albumArtRoles('daft punk', 'Random Access Memories!'), {'disc': 'http://x/cd.jpg'},
        reason: 'the same record spelled slightly differently is the same record');
  });

  test('one image cannot be two things', () async {
    const img = 'http://x/one.jpg';
    await lib.setAlbumArtRole('X', 'Rec', 'back', img);
    await lib.setAlbumArtRole('X', 'Rec', 'disc', img);
    expect(lib.albumArtRoles('X', 'Rec'), {'disc': img},
        reason: 'assigning a scan to a second role takes it off the first');
  });

  test('an empty url clears that role and lets the app guess again', () async {
    await lib.setAlbumArtRole('X', 'Rec', 'front', 'http://x/f.jpg');
    await lib.setAlbumArtRole('X', 'Rec', 'back', 'http://x/b.jpg');
    await lib.setAlbumArtRole('X', 'Rec', 'front', '');
    expect(lib.albumArtRoles('X', 'Rec'), {'back': 'http://x/b.jpg'});

    await lib.setAlbumArtRole('X', 'Rec', 'back', '');
    expect(lib.albumArtRoles('X', 'Rec'), isEmpty,
        reason: 'the last role cleared leaves nothing behind');
  });

  test('two records keep their own answers', () async {
    await lib.setAlbumArtRole('A', 'One', 'front', 'http://a/1.jpg');
    await lib.setAlbumArtRole('B', 'Two', 'front', 'http://b/1.jpg');
    expect(lib.albumArtRoles('A', 'One'), {'front': 'http://a/1.jpg'});
    expect(lib.albumArtRoles('B', 'Two'), {'front': 'http://b/1.jpg'});
  });

  test('what is written is readable json, not a blob', () async {
    await lib.setAlbumArtRole('X', 'Rec', 'front', 'http://x/f.jpg');
    final f = File('${lib.configDirOverride}${Platform.pathSeparator}album_art_roles.json');
    expect(await f.exists(), isTrue);
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    expect(j.values.first, {'front': 'http://x/f.jpg'});
  });

  /// Choosing an EDITION and overruling one of its scans are different acts, and one has to win.
  ///
  /// A role outranks the pinned pressing — that is what makes it an override. So a sleeve picked
  /// once from the digital release went on winning after the user deliberately chose the CD, and the
  /// tick on a row looked like it did nothing at all.
  group('choosing an edition starts from that edition', () {
    test('it drops the scans picked by hand', () async {
      await lib.setAlbumArtRole('Yasmine', 'Prêt-à-porter', 'front', 'http://digital/front.jpg');
      await lib.setAlbumArtRole('Yasmine', 'Prêt-à-porter', 'disc', 'http://cd/disc.jpg');
      expect(lib.albumArtRoles('Yasmine', 'Prêt-à-porter'), isNotEmpty);

      // What the tick on a gallery row does before it pins the pressing.
      await lib.clearAlbumArtRoles('Yasmine', 'Prêt-à-porter');

      expect(lib.albumArtRoles('Yasmine', 'Prêt-à-porter'), isEmpty,
          reason: 'anders houdt de oude hoes de nieuwe uitgave tegen');
    });

    test('and leaves every other record alone', () async {
      await lib.setAlbumArtRole('Yasmine', 'Prêt-à-porter', 'front', 'http://digital/front.jpg');
      await lib.setAlbumArtRole('Garou', 'Seul', 'disc', 'http://cd/seul.jpg');

      await lib.clearAlbumArtRoles('Yasmine', 'Prêt-à-porter');

      expect(lib.albumArtRoles('Yasmine', 'Prêt-à-porter'), isEmpty);
      expect(lib.albumArtRoles('Garou', 'Seul'), {'disc': 'http://cd/seul.jpg'});
    });

    test('clearing is written down, and clearing nothing is not an error', () async {
      await lib.setAlbumArtRole('X', 'Rec', 'front', 'http://x/f.jpg');
      await lib.clearAlbumArtRoles('X', 'Rec');
      await lib.clearAlbumArtRoles('X', 'Rec'); // must not throw

      final again = LibraryStore()..configDirOverride = lib.configDirOverride;
      await again.loadAlbumArtRoles();
      expect(again.albumArtRoles('X', 'Rec'), isEmpty);
    });
  });

  // Saber, 28-10-2026: "als ik bij album detail screen metadata wil corrigeren, dan past hij de hoes, cd
  // achterkant niet mee aan?" "Metadata corrigeren" zette de nieuwe persing vast en liet je oude scans winnen.
  group('Metadata corrigeren: een andere persing neemt haar eigen scans', () {
    test('een andere Discogs-persing wisselt, dezelfde niet', () {
      expect(LibraryStore.wisseltPersing(nieuweRelease: 9452134, huidigeRelease: 3190165), isTrue);
      expect(LibraryStore.wisseltPersing(nieuweRelease: 9452134, huidigeRelease: 9452134), isFalse,
          reason: 'dezelfde persing nog eens kiezen laat je scans staan');
      expect(LibraryStore.wisseltPersing(nieuweRelease: 9452134), isTrue,
          reason: 'nog niets vastgezet: de eerste persing is ook een wissel');
    });

    test('MusicBrainz net zo, zonder op hoofdletters te letten', () {
      const a = '0d36931b-0000-4000-8000-000000000001', b = 'f7499a40-0000-4000-8000-000000000002';
      expect(LibraryStore.wisseltPersing(nieuweMbid: b, huidigeMbid: a), isTrue);
      expect(LibraryStore.wisseltPersing(nieuweMbid: a.toUpperCase(), huidigeMbid: a), isFalse);
    });

    test('van de ene catalogus naar de andere is een wissel', () {
      // applyCorrection haalt de MusicBrainz-pin weg zodra er een Discogs-persing komt, en omgekeerd.
      expect(
          LibraryStore.wisseltPersing(nieuweRelease: 9452134, huidigeRelease: 9452134, huidigeMbid: 'abc'),
          isTrue);
      expect(LibraryStore.wisseltPersing(nieuweMbid: 'abc', huidigeRelease: 9452134), isTrue);
    });

    test('DE GRENS: geen persing (Deezer, TheAudioDB, alleen een naam) wisselt niets', () {
      expect(LibraryStore.wisseltPersing(huidigeRelease: 9452134), isFalse);
      expect(LibraryStore.wisseltPersing(nieuweRelease: 0, nieuweMbid: '', huidigeMbid: 'abc'), isFalse);
      expect(LibraryStore.wisseltPersing(), isFalse);
    });

    String toepassen() {
      final bron = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final begin = bron.indexOf('  Future<void> _applyInner() async {');
      expect(begin, isNonNegative);
      return bron.substring(begin, bron.indexOf('\n  }\n', begin));
    }

    test('DE KERN: het venster wist de scans vóór de correctie, alleen bij een hele plaat', () {
      final lijf = toepassen();
      final wis = lijf.indexOf('await lib.clearAlbumArtRoles(widget.album.artist, widget.album.title);');
      expect(wis, isNonNegative, reason: 'anders blijven je oude achterkant en cd van de nieuwe persing winnen');
      expect(lijf.substring(0, wis), contains('if (los == null &&\n        LibraryStore.wisseltPersing('),
          reason: 'één aangewezen nummer verhuist; de scans horen bij het album dat blijft');
      expect(wis, lessThan(lijf.indexOf('await lib.applyCorrection(')),
          reason: 'eerst wissen: applyCorrection neemt wat er staat mee naar de nieuwe naam');
    });

    test('DE KERN: Toepassen wacht op de hoes van de aangewezen rij', () {
      final lijf = toepassen();
      final wacht = lijf.indexOf('await hoes.timeout(const Duration(seconds: 20));');
      expect(wacht, isNonNegative, reason: 'snel op Toepassen drukken gaf je vorige voorkant terug');
      expect(wacht, lessThan(lijf.indexOf('coverBytes: _pickedCover,')));
    });
  });
}
