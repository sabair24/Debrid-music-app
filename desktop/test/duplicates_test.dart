import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/settings.dart';

/// A real file on disk, because redundancy is decided partly by file size (firstIsBetter).
Track _mk(Directory root, String folder, String file,
    {required String artist,
    required String album,
    required String title,
    int no = 1,
    int secs = 200,
    int kb = 100,
    bool single = false}) {
  // The folders are written with backslashes because that is how they read on the machine this
  // library lives on. On macOS a backslash is an ordinary character, so `Albums\BSB\Backstreet
  // Boys` became ONE directory with that literal name — while the assertions below build the path
  // with Platform.pathSeparator and looked for a folder that could never exist. The test has never
  // run anywhere but Windows.
  final folderPath = folder.replaceAll(r'\', Platform.pathSeparator);
  final d = Directory('${root.path}${Platform.pathSeparator}$folderPath')
    ..createSync(recursive: true);
  final f = File('${d.path}${Platform.pathSeparator}$file')..writeAsBytesSync(List.filled(kb * 1024, 7));
  return Track(
    path: f.path,
    title: title,
    artist: artist,
    album: single ? '' : album,
    trackNo: no,
    duration: Duration(seconds: secs),
    isFlac: file.endsWith('.flac'),
  );
}

void main() {
  late Directory root;
  late LibraryStore lib;
  setUp(() {
    root = Directory.systemTemp.createTempSync('dupes');
    lib = LibraryStore()..configDirOverride = '${root.path}${Platform.pathSeparator}_cfg';
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// The real 13-track album, with three of its tracks named as the fixtures need.
  List<Track> _mainAlbum() => [
        for (var i = 1; i <= 13; i++)
          _mk(root, r'Albums\BSB\Backstreet Boys', '${i.toString().padLeft(2, '0')} - t$i.flac',
              artist: 'Backstreet Boys',
              album: 'Backstreet Boys',
              title: i == 2
                  ? 'Anywhere for You'
                  : i == 9
                      ? 'Every Time I Close My Eyes'
                      : i == 10
                          ? 'Darlin'
                          : i == 13
                              ? 'Nobody but You'
                              : 't$i',
              no: i,
              secs: 200 + i,
              kb: 100),
      ];

  group('redundantAlbums', () {
    test('a Special-Edition fragment is folded into the full album, better copy winning', () {
      final ts = <Track>[
        ..._mainAlbum(),
        // The fragment: 9, 10, 13 — same recordings, but BIGGER files (higher bitrate here).
        _mk(root, r'Albums\BSB\Backstreet Boys (Special Edition)', '09 - Every Time.flac',
            artist: 'Backstreet Boys', album: 'Backstreet Boys (Special Edition)',
            title: 'Every Time I Close My Eyes', no: 9, secs: 209, kb: 400),
        _mk(root, r'Albums\BSB\Backstreet Boys (Special Edition)', '10 - Darlin.flac',
            artist: 'Backstreet Boys', album: 'Backstreet Boys (Special Edition)',
            title: 'Darlin', no: 10, secs: 210, kb: 400),
        _mk(root, r'Albums\BSB\Backstreet Boys (Special Edition)', '13 - Nobody.flac',
            artist: 'Backstreet Boys', album: 'Backstreet Boys (Special Edition)',
            title: 'Nobody but You', no: 13, secs: 213, kb: 400),
      ];
      lib.tracks.addAll(ts);
      lib.rebuildAlbums();

      final red = lib.redundantAlbums();
      expect(red, hasLength(1));
      final r = red.single;
      expect(r.source.title, 'Backstreet Boys (Special Edition)');
      expect(r.target.title, 'Backstreet Boys');
      expect(r.pairs, hasLength(3));
      // Every fragment copy is bigger here, so every one wins and will replace what's owned.
      expect(r.upgrades, 3, reason: 'the higher-bitrate fragment copies are the keepers');
      expect(r.pairs.every((p) => p.dupWins), isTrue);
    });

    test('a junk WAV single filed under the wrong artist is still recognised', () {
      final ts = <Track>[
        ..._mainAlbum(),
        // Tags unreadable → filed as an unknown-artist single, filename as title.
        _mk(root, r'Singles\Onbekende artiest', '20 Backstreet Boys - Anywhere for You.wav',
            artist: 'Onbekende artiest', album: '', title: '20 Backstreet Boys - Anywhere for You',
            no: 1, secs: 203, kb: 500, single: true),
      ];
      lib.tracks.addAll(ts);
      lib.rebuildAlbums();

      final red = lib.redundantAlbums();
      expect(red, hasLength(1));
      expect(red.single.source.isSingle, isTrue);
      expect(red.single.target.title, 'Backstreet Boys');
      expect(red.single.pairs.single.owned.title, 'Anywhere for You');
    });

    test('a real greatest-hits sharing SOME tracks is left completely alone', () {
      final ts = <Track>[
        ..._mainAlbum(),
        // A compilation: two tracks from the album, plus one from a different record it does not own
        // in full. It is NOT wholly contained in any studio album, and it is a compilation by name.
        _mk(root, r'Albums\BSB\Greatest Hits', '01 - Anywhere.flac',
            artist: 'Backstreet Boys', album: 'Greatest Hits', title: 'Anywhere for You', no: 1, secs: 202),
        _mk(root, r'Albums\BSB\Greatest Hits', '02 - Nobody.flac',
            artist: 'Backstreet Boys', album: 'Greatest Hits', title: 'Nobody but You', no: 2, secs: 213),
        _mk(root, r'Albums\BSB\Greatest Hits', '03 - Larger.flac',
            artist: 'Backstreet Boys', album: 'Greatest Hits', title: 'Larger Than Life', no: 3, secs: 230),
      ];
      lib.tracks.addAll(ts);
      lib.rebuildAlbums();
      expect(lib.redundantAlbums(), isEmpty,
          reason: 'a compilation you chose must never be swept away');
    });

    test('a live album is never folded into the studio record', () {
      // Alizée: a live "Gourmandises" whose track tag lacks any (live) marker — only the album name
      // says it is a concert. Folding it would silently lose the live take.
      final ts = <Track>[
        _mk(root, r'Albums\Alizee\Gourmandises', '09 - Gourmandises.flac',
            artist: 'Alizée', album: 'Gourmandises', title: 'Gourmandises', no: 9, secs: 230, kb: 500),
        _mk(root, r'Albums\Alizee\Alizée en concert', '07 - Gourmandises.flac',
            artist: 'Alizée', album: 'Alizée en concert', title: 'Gourmandises', no: 7, secs: 232, kb: 300),
      ];
      lib.tracks.addAll(ts);
      lib.rebuildAlbums();
      expect(lib.redundantAlbums(), isEmpty,
          reason: 'a live recording is a distinct release, kept like a compilation');
    });

    test('a genuine, unique single is not touched', () {
      final ts = <Track>[
        ..._mainAlbum(),
        _mk(root, r'Singles\Some Artist', 'A Song Nobody Owns Twice.flac',
            artist: 'Some Artist', album: '', title: 'A Song Nobody Owns Twice', single: true),
      ];
      lib.tracks.addAll(ts);
      lib.rebuildAlbums();
      expect(lib.redundantAlbums(), isEmpty);
    });
  });

  group('consolidate', () {
    test('one album remains, the best copy kept, the rest parked in _dubbel', () async {
      final main = _mainAlbum();
      final frag = [
        _mk(root, r'Albums\BSB\Backstreet Boys (Special Edition)', '09 - Every Time.flac',
            artist: 'Backstreet Boys', album: 'Backstreet Boys (Special Edition)',
            title: 'Every Time I Close My Eyes', no: 9, secs: 209, kb: 400),
        _mk(root, r'Albums\BSB\Backstreet Boys (Special Edition)', '10 - Darlin.flac',
            artist: 'Backstreet Boys', album: 'Backstreet Boys (Special Edition)',
            title: 'Darlin', no: 10, secs: 210, kb: 400),
        _mk(root, r'Albums\BSB\Backstreet Boys (Special Edition)', '13 - Nobody.flac',
            artist: 'Backstreet Boys', album: 'Backstreet Boys (Special Edition)',
            title: 'Nobody but You', no: 13, secs: 213, kb: 400),
      ];
      lib
        ..rootPath = root.path
        ..tracks.addAll([...main, ...frag]);
      lib.rebuildAlbums();

      final r = lib.redundantAlbums().single;
      await lib.consolidate(r);

      final mainDir = Directory('${root.path}${Platform.pathSeparator}Albums${Platform.pathSeparator}BSB${Platform.pathSeparator}Backstreet Boys');
      final flacs = mainDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.flac'))
          .toList();
      expect(flacs, hasLength(13), reason: 'still exactly the 13-track album, no extras');

      // The bigger fragment copies won and are now the ones in the album folder.
      for (final n in ['09', '10', '13']) {
        final kept = flacs.firstWhere((f) => f.uri.pathSegments.last.startsWith(n));
        expect(kept.lengthSync(), 400 * 1024, reason: 'track $n: the higher-bitrate copy is kept');
      }
      // The three copies they beat are parked, nothing deleted.
      final dubbel = Directory('${mainDir.path}${Platform.pathSeparator}$dupeFolder');
      expect(dubbel.existsSync(), isTrue);
      expect(dubbel.listSync().whereType<File>(), hasLength(3));

      // The Special Edition folder is gone.
      expect(
          Directory('${root.path}${Platform.pathSeparator}Albums${Platform.pathSeparator}BSB${Platform.pathSeparator}Backstreet Boys (Special Edition)').existsSync(),
          isFalse);
      // (The library grouping after the rescan can't be checked here — these fixtures aren't real
      //  FLAC, so the scan reads no tags. The disk state above is the truth; grouping is covered by
      //  the detection tests, which build the albums directly.)
    });
  });
}
