import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Where this app keeps everything that is not music: settings, corrections, cover cache,
/// the resume queue, the shared state.
///
/// One place, because there were ten copies of the same expression and they all fell back to the
/// *working directory* when `APPDATA` was unset — which is fine on Windows, where it never is,
/// but on a Mac it scattered a `DebridMusic/` folder wherever the app happened to be started
/// from, and did the same in the repository during tests.
///
/// Resolved once at startup so the callers can stay synchronous getters. On iOS the sandbox path
/// cannot be worked out from the environment at all, so [initAppPaths] has to run before anything
/// reads it — [appDir] falls back to a sensible guess rather than throwing, so a unit test that
/// forgets is merely writing somewhere harmless instead of crashing.
String? _resolved;

/// Call once, early in `main()`, before any settings or caches are read.
Future<void> initAppPaths() async {
  if (Platform.isWindows) {
    // Unchanged on purpose: an existing install must keep finding its own data.
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      _resolved = '$appData${Platform.pathSeparator}DebridMusic';
      return;
    }
  }
  try {
    final dir = await getApplicationSupportDirectory();
    _resolved = '${dir.path}${Platform.pathSeparator}DebridMusic';
  } catch (_) {
    _resolved = _fallback();
  }
  await Directory(_resolved!).create(recursive: true);
}

/// The folder to write to. Safe to read before [initAppPaths] has finished.
String get appDir => _resolved ??= _fallback();

/// Point everything at a scratch folder for the duration of a test.
///
/// Without this a test run writes into the REAL cover cache and the real corrections file — the
/// user's hand-made metadata — because [_fallback] resolves to the same place the app uses.
@visibleForTesting
void setAppDirForTest(String path) => _resolved = path;

/// A file inside it.
File appFile(String name) => File('$appDir${Platform.pathSeparator}$name');

/// A subfolder inside it, created on demand.
Directory appSubdir(String name) =>
    Directory('$appDir${Platform.pathSeparator}$name')..createSync(recursive: true);

String _fallback() {
  final appData = Platform.environment['APPDATA'];
  if (appData != null && appData.isNotEmpty) {
    return '$appData${Platform.pathSeparator}DebridMusic';
  }
  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    // The macOS convention. On iOS this is never reached — there the sandbox path comes from
    // path_provider, and initAppPaths runs before anything asks.
    return Platform.isMacOS
        ? '$home/Library/Application Support/DebridMusic'
        : '$home${Platform.pathSeparator}.debridmusic';
  }
  return '${Directory.systemTemp.path}${Platform.pathSeparator}DebridMusic';
}
