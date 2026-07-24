import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';

/// Real files on disk: which copy survives a collision is decided by `firstIsBetter`, and that
/// reads their size off the filesystem.
Track _mk(Directory root, String folder, String file,
    {required String artist,
    required String album,
    required String title,
    required int secs,
    int no = 1,
    int total = 0,
    int kb = 100}) {
  final d = Directory('${root.path}${Platform.pathSeparator}$folder')..createSync(recursive: true);
  final f = File('${d.path}${Platform.pathSeparator}$file')
    ..writeAsBytesSync(List.filled(kb * 1024, 7));
  return Track(
    path: f.path,
    title: title,
    artist: artist,
    album: album,
    trackNo: no,
    trackTotal: total,
    duration: Duration(seconds: secs),
    isFlac: file.endsWith('.flac'),
  );
}

void main() {
  late Directory root;
  late LibraryStore lib;
  setUp(() {
    root = Directory.systemTemp.createTempSync('dedupe');
    lib = LibraryStore()..configDirOverride = '${root.path}${Platform.pathSeparator}_cfg';
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// The real case. Two files of one song sat in the library: the 2:45 album cut, and the 4:41
  /// "(D'N'D Full Length Version)". A hand-written correction retitled the second to the plain
  /// album title to get it onto track 3 — and that gave the two the same artist+title.
  List<Track> bedingfieldPair() => [
        _mk(root, r'complete\Cynetix\[2003] Gotta Get Thru This',
            '03 - Gotta Get Thru This.flac',
            artist: 'Daniel Bedingfield',
            album: 'Gotta Get Thru This',
            title: 'Gotta Get Thru This',
            no: 3,
            total: 13,
            secs: 165,
            kb: 200),
        _mk(root, r'complete\lempamo\{2002} Gotta Get Thru This',
            "02 - Gotta Get Thru This (D'N'D Full Length Version).flac",
            artist: 'Daniel Bedingfield',
            album: 'Gotta Get Thru This',
            // The corrected title — this is what the grouping actually sees.
            title: 'Gotta Get Thru This',
            no: 3,
            total: 13,
            secs: 281,
            kb: 340),
      ];

  group('een titelbotsing laat geen muziek verdwijnen', () {
    test('de albumversie blijft staan als een correctie een variant dezelfde titel geeft', () {
      final ts = bedingfieldPair();
      lib.tracks.addAll(ts);
      lib.rebuildAlbums();

      final album = lib.albums.single;
      expect(album.tracks.map((t) => t.path), containsAll(ts.map((t) => t.path)),
          reason: 'de 2:45-versie werd opgegeten door de 4:41 met dezelfde titel');
    });

    test('de kopbalk telt niet meer nummers dan de albums samen tonen', () {
      lib.tracks.addAll(bedingfieldPair());
      lib.rebuildAlbums();

      final onPages = lib.albums.fold<int>(0, (n, a) => n + a.tracks.length);
      expect(onPages, lib.tracks.length,
          reason: 'een spoor dat nergens op een albumpagina staat telt wel mee in de kop');
    });

    test('elk spoor dat de app toont hoort bij een album, en is dus te verplaatsen', () {
      final ts = bedingfieldPair();
      lib.tracks.addAll(ts);
      lib.rebuildAlbums();

      for (final t in ts) {
        expect(lib.albumForPath(t.path), isNotNull,
            reason: 'zonder album is de verplaatsknop stil dood: ${t.path}');
      }
    });
  });

  group('wat wel een opname is blijft een rij', () {
    test('twee rips van dezelfde take vouwen samen, de betere wint', () {
      final small = _mk(root, r'complete\rip-a', '01 - Song.flac',
          artist: 'X', album: 'Rec', title: 'Song', secs: 200, kb: 100);
      final big = _mk(root, r'complete\rip-b', '01 - Song.flac',
          artist: 'X', album: 'Rec', title: 'Song', secs: 202, kb: 400);
      lib.tracks.addAll([small, big]);
      lib.rebuildAlbums();

      final album = lib.albums.single;
      expect(album.tracks, hasLength(1), reason: 'dezelfde take hoort een rij te zijn');
      expect(album.tracks.single.path, big.path, reason: 'de grootste kopie hoort te winnen');
    });

    test('een duur die niemand rapporteert houdt het oude gedrag aan', () {
      final a = _mk(root, r'complete\rip-a', '01 - Song.flac',
          artist: 'X', album: 'Rec', title: 'Song', secs: 0, kb: 100);
      final b = _mk(root, r'complete\rip-b', '01 - Song.flac',
          artist: 'X', album: 'Rec', title: 'Song', secs: 0, kb: 400);
      lib.tracks.addAll([a, b]);
      lib.rebuildAlbums();

      expect(lib.albums.single.tracks, hasLength(1),
          reason: 'zonder duren is er geen bewijs van twee takes — niet ineens verdubbelen');
    });

    test('een radio-edit naast de albumcut is nog steeds geen tweede persing', () {
      lib.tracks.addAll([
        _mk(root, r'complete\album', '01 - Everybody.flac',
            artist: 'BSB',
            album: 'Backstreets Back',
            title: 'Everybody',
            no: 1,
            total: 11,
            secs: 228),
        _mk(root, r'complete\album', '01 - Everybody (Radio Edit).flac',
            artist: 'BSB',
            album: 'Backstreets Back',
            title: 'Everybody (Radio Edit)',
            no: 1,
            total: 11,
            secs: 199),
      ]);
      lib.rebuildAlbums();

      expect(lib.albums, hasLength(1), reason: 'een plaat, geen twee tegels');
      expect(lib.albums.single.edition, isNull);
    });
  });

  group('recordingElsewhere', () {
    /// The rip that got downloaded twice: no ALBUM tag, so it sits in its own single, and its
    /// version is written with a dash where the catalogue uses brackets.
    Track looseRip() => _mk(root, r'complete\f4mes',
        "Gotta Get Thru This - D'N'D Radio Edit - Daniel Bedingfield, D'N'D Productions.flac",
        artist: "Daniel Bedingfield, D'N'D Productions",
        album: '',
        title: "Gotta Get Thru This - D'N'D Radio Edit",
        secs: 161);

    test('vindt een kopie die met een streepje geschreven staat onder een samengestelde artiest',
        () {
      final mine = looseRip();
      lib.tracks.add(mine);
      lib.rebuildAlbums();

      final found = lib.recordingElsewhere(
          'Daniel Bedingfield', "Gotta Get Thru This (D'n'D radio edit)",
          seconds: 161);
      expect(found?.path, mine.path,
          reason: 'precies deze mismatch liet de app het nummer een tweede keer downloaden');
    });

    test('een duur die niet klopt is een ander nummer, geen kopie', () {
      lib.tracks.add(looseRip());
      lib.rebuildAlbums();

      expect(
          lib.recordingElsewhere('Daniel Bedingfield', "Gotta Get Thru This - D'N'D Radio Edit",
              seconds: 281),
          isNull,
          reason: 'de 4:41 full length is niet dezelfde opname als de 2:41 edit');
    });

    test('de bestanden van de pagina zelf tellen niet als elders', () {
      final mine = looseRip();
      lib.tracks.add(mine);
      lib.rebuildAlbums();

      expect(
          lib.recordingElsewhere('Daniel Bedingfield', "Gotta Get Thru This - D'N'D Radio Edit",
              seconds: 161, exclude: {mine.path}),
          isNull);
    });

    test('een andere artiest met dezelfde titel is geen kopie', () {
      lib.tracks.add(_mk(root, r'complete\ander', '01 - Angel.flac',
          artist: 'Massive Attack', album: 'Mezzanine', title: 'Angel', secs: 380));
      lib.rebuildAlbums();

      expect(lib.recordingElsewhere('Robbie Williams', 'Angel', seconds: 380), isNull);
    });
  });
}
