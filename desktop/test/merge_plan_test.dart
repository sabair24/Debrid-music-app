import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/settings.dart';

/// A real file on disk, because the plan asks the filesystem which copy is better.
Track _mk(Directory root, String folder, String file, {int kb = 100, int no = 1}) {
  final d = Directory('${root.path}${Platform.pathSeparator}$folder')..createSync(recursive: true);
  final f = File('${d.path}${Platform.pathSeparator}$file')
    ..writeAsBytesSync(List.filled(kb * 1024, 7));
  return Track(
    path: f.path,
    title: file.replaceAll(RegExp(r'^\d+ - |\.\w+$'), ''),
    artist: 'Backstreet Boys',
    album: "Backstreet's Back",
    trackNo: no,
    isFlac: file.endsWith('.flac'),
  );
}

Album _album(List<Track> ts) => Album("Backstreet's Back", 'Backstreet Boys', ts);

void main() {
  late Directory root;
  late LibraryStore lib;

  setUp(() {
    root = Directory.systemTemp.createTempSync('mergeplan');
    lib = LibraryStore();
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('planMerge', () {
    test('gathers into the folder that already holds the most of the record', () {
      final a = _album([
        _mk(root, 'Backstreet\'s Back', '01 - Everybody.flac', no: 1),
        _mk(root, 'Backstreet\'s Back', '02 - As Long As You Love Me.flac', no: 2),
        _mk(root, 'BSB soulseek rip', '03 - All I Have To Give.flac', no: 3),
      ]);

      final plan = lib.planMerge(a);

      expect(plan.folder, endsWith("Backstreet's Back"));
      expect(plan.moving, 1, reason: 'only the stray file needs to travel');
      expect(plan.staying, 2);
      expect(plan.parking, 0);
      expect(plan.items.firstWhere((i) => i.fate == MoveFate.moves).name,
          '03 - All I Have To Give.flac');
    });

    test('a tie goes to the folder named like the album', () {
      final a = _album([
        _mk(root, 'zz random download', '01 - Everybody.flac', no: 1),
        _mk(root, "Backstreet's Back", '02 - As Long As You Love Me.flac', no: 2),
      ]);

      expect(lib.planMerge(a).folder, endsWith("Backstreet's Back"));
    });

    test('a name collision parks the worse copy in _dubbel, and nothing is lost', () {
      // Same track name in two folders: a big FLAC and a small one. The big one wins the name.
      final small = _mk(root, "Backstreet's Back", '01 - Everybody.flac', kb: 50, no: 1);
      final filler = _mk(root, "Backstreet's Back", '02 - As Long.flac', no: 2);
      final big = _mk(root, 'BSB deluxe', '01 - Everybody.flac', kb: 900, no: 1);

      final plan = lib.planMerge(_album([small, filler, big]));

      expect(plan.folder, endsWith("Backstreet's Back"));
      // The bigger copy takes the plain name; the smaller one is bumped into _dubbel.
      final winner = plan.items.firstWhere((i) => i.from == big.path);
      final loser = plan.items.firstWhere((i) => i.from == small.path);
      expect(winner.fate, MoveFate.moves);
      expect(winner.to, isNot(contains(dupeFolder)));
      expect(loser.fate, MoveFate.toDupes);
      expect(loser.to, contains(dupeFolder));
      // Every file is accounted for exactly once — a plan that drops one is worse than no plan.
      expect(plan.items.length, 3);
      expect(plan.items.map((i) => i.from).toSet().length, 3);
    });

    test('the bumped tenant is listed once, whichever order the tracks come in', () {
      // The sitting copy comes LAST in the list, so it is bumped before the loop reaches it. It
      // used to be planned twice — once into _dubbel, once as staying — which made the plan
      // uncheckable and inflated the "blijft staan" count.
      final big = _mk(root, 'BSB deluxe', '01 - Everybody.flac', kb: 900, no: 1);
      final filler = _mk(root, "Backstreet's Back", '02 - As Long.flac', no: 2);
      final small = _mk(root, "Backstreet's Back", '01 - Everybody.flac', kb: 50, no: 1);

      final plan = lib.planMerge(_album([big, filler, small]));

      expect(plan.items.length, 3);
      expect(plan.items.map((i) => i.from).toSet().length, 3, reason: 'no file listed twice');
      expect(plan.items.where((i) => i.from == small.path).single.fate, MoveFate.toDupes);
      expect(plan.items.where((i) => i.from == big.path).single.fate, MoveFate.moves);
      expect(plan.staying, 1, reason: 'only the filler stays');
      expect(plan.summary, '1 verhuist · 1 naar $dupeFolder · 1 blijft staan');
    });

    test('a stranger already holding the name is never overwritten', () {
      final mine = _mk(root, 'BSB elders', '01 - Everybody.flac', kb: 900, no: 1);
      final home = _mk(root, "Backstreet's Back", '02 - As Long.flac', no: 2);
      // Not one of our tracks — some other file that happens to share the name.
      File('${File(home.path).parent.path}${Platform.pathSeparator}01 - Everybody.flac')
          .writeAsBytesSync(List.filled(10, 1));

      final plan = lib.planMerge(_album([mine, home]));

      final p = plan.items.firstWhere((i) => i.from == mine.path);
      expect(p.fate, MoveFate.toDupes, reason: 'step aside rather than replace a file we did not put there');
      expect(p.to, contains(dupeFolder));
    });

    test('already in one folder is a no-op', () {
      final plan = lib.planMerge(_album([
        _mk(root, "Backstreet's Back", '01 - Everybody.flac', no: 1),
        _mk(root, "Backstreet's Back", '02 - As Long.flac', no: 2),
      ]));

      expect(plan.isNoop, isTrue);
      expect(plan.summary, '2 blijven staan');
    });

    test('an album with no tracks plans nothing rather than throwing', () {
      final plan = lib.planMerge(Album('Leeg', 'Niemand', const []));
      expect(plan.folder, isNull);
      expect(plan.items, isEmpty);
      expect(plan.isNoop, isTrue);
    });
  });

  group('corrections follow the file', () {
    test('a moved track keeps its album correction — and its pinned release', () async {
      final stray = _mk(root, 'losse map', '05 - Get Down.flac', no: 5);
      final target = _album([_mk(root, "Backstreet's Back", '01 - Everybody.flac', no: 1)]);

      // The library only knows tracks it has scanned.
      lib.tracks.addAll([stray, ...target.tracks]);
      lib.rebuildAlbums();
      // A pin the user set earlier on the track that is about to travel.
      lib.seedCorrectionForTest(stray.path, {'release': '21047161'});

      lib.rootPath = root.path;
      // Never the real %APPDATA% — see configDirOverride.
      lib.configDirOverride = '${root.path}${Platform.pathSeparator}_config';
      await lib.moveTracksToAlbum([stray], target, AppSettings(), moveFiles: true);

      final landed =
          '${File(target.tracks.first.path).parent.path}${Platform.pathSeparator}05 - Get Down.flac';
      expect(File(landed).existsSync(), isTrue, reason: 'the file itself moved');
      expect(File(stray.path).existsSync(), isFalse);

      // The point of the fix: the correction is readable at the NEW path, pin included.
      final now = lib.correctionForTest(landed);
      expect(now, isNotNull, reason: 'a correction left at the old path is dead on the next scan');
      expect(now!['album'], "Backstreet's Back");
      expect(now['release'], '21047161', reason: 'moving a track must not cost it its pinned pressing');
      expect(lib.correctionForTest(stray.path), isNull, reason: 'no orphan left behind');
    });
  });
}
