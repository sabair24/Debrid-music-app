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
library;

import 'dart:async';
import 'dart:io';

import 'package:debridmusic/paths.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final scratch = Directory.systemTemp.createTempSync('dm_testrun_');
  setAppDirForTest(scratch.path);
  try {
    await testMain();
  } finally {
    // Best effort: a test that left a file open on Windows must not fail the run over cleanup.
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  }
}
