/// Every test writes to a scratch folder. No exceptions, no remembering.
///
/// `flutter_test` runs this before the `main()` of every test file in this directory, so it is the
/// one place where "the tests must not touch the user's data" can be made true instead of asked
/// for.
///
/// **Why it has to be here and not in each test.** [appDir] falls back to the app's REAL folder
/// when nothing redirects it — on Windows that is `%APPDATA%\DebridMusic`, which holds
/// `settings.json` with the Soulseek and RuTracker passwords, `corrections.json` with every
/// metadata edit ever made by hand, and the cover caches. Nineteen test files construct a
/// `LibraryStore`, an `AppSettings` or a `SoulseekService` without redirecting anything, and one of
/// them reaches a code path that calls `settings.save()` — which would write an object whose every
/// field is empty straight over the real file.
///
/// It was found by deleting `~/Library/Application Support/DebridMusic` on a Mac and watching four
/// tests recreate it. On macOS the app itself lives in a sandbox container, so the damage was only
/// a confusing second folder. On Windows there is no container and the two are the same place.
///
/// A per-test `setAppDirForTest` fixes the file it is written in and nothing else; the next test
/// someone adds starts the problem over. This cannot be forgotten.
///
/// **En elk toetsbestand één eigen tijdelijke map (Saber, 04-11-2026: "lek dichten ook").** Op 04-11-2026 stonden er
/// 58.318 `dm_*`-mappen in %TEMP% (24 GB), 3.831 uit de laatste twee dagen: `Directory.systemTemp.createTempSync` in
/// honderden toetsen, en code die na de toets nog schrijft en een gewiste map opnieuw aanmaakt
/// ([[tijdelijke-mappen-van-toetsen]]). Nu wijst `Directory.systemTemp` binnen een toetsbestand naar
/// `dm_toetsbestand_*`; die gaat na de laatste toets in één keer weg, en wat een late schrijver toch nog achterliet,
/// ruimt de volgende run op (ouder dan [_oudNa]).
library;

import 'dart:async';
import 'dart:io';

import 'package:debridmusic/paths.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een eigen map van een vorige run die ouder is dan dit, wordt bij het begin weggeruimd: geen run duurt zo lang.
const _oudNa = Duration(hours: 3);

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final echt = Directory.systemTemp;
  _ruimOudeOp(echt);
  final eigen = echt.createTempSync('dm_toetsbestand_');
  final scratch = Directory('${eigen.path}${Platform.pathSeparator}app')..createSync();
  setAppDirForTest(scratch.path);
  // Globaal en niet in een zone: de toetsen zelf draaien in zones die niet van de declaratie afstammen (gemeten:
  // IOOverrides.runZoned bereikte geen enkele toets).
  IOOverrides.global = _EigenTemp(eigen);
  tearDownAll(() async {
    // Late schrijvers (uitgestelde opslag) kunnen nog net iets aanmaken: een paar keer proberen, niet lang wachten.
    for (var i = 0; i < 5 && eigen.existsSync(); i++) {
      try {
        eigen.deleteSync(recursive: true);
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });
  await testMain();
}

/// `Directory.systemTemp` wijst naar de eigen map van dit toetsbestand; verder alles zoals het is.
final class _EigenTemp extends IOOverrides {
  _EigenTemp(this.map);
  final Directory map;

  @override
  Directory getSystemTempDirectory() => map;
}

/// Wat vorige runs achterlieten in hun eigen map ([testExecutable]), als het ouder is dan [_oudNa].
void _ruimOudeOp(Directory echt) {
  final grens = DateTime.now().subtract(_oudNa);
  try {
    for (final e in echt.listSync(followLinks: false)) {
      if (e is! Directory || !e.path.split(Platform.pathSeparator).last.startsWith('dm_toetsbestand_')) continue;
      try {
        if (e.statSync().modified.isBefore(grens)) e.deleteSync(recursive: true);
      } catch (_) {/* in gebruik: de volgende keer */}
    }
  } catch (_) {}
}
