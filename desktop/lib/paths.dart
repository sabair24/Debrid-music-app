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

  // En de plek voor logboeken, die op Android een andere is. Zie [logDir].
  if (Platform.isAndroid) {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        await ext.create(recursive: true);
        _logMap = ext.path;
      }
    } catch (_) {
      // Dan maar in appDir. Onleesbaar is nog altijd beter dan een app die niet start.
    }
  }
}

/// The folder to write to. Safe to read before [initAppPaths] has finished.
String get appDir => _resolved ??= _fallback();

/// Waar diagnostische logboeken heen gaan.
///
/// Op Android met opzet NIET [appDir]. Die map is op een release-build met `adb` niet te lezen:
///
///     ls /data/data/com.debridmusic.app/files/DebridMusic/
///     ls: Permission denied
///
/// En een logboek dat niemand kan lezen bewijst niets — precies waar `WarmLog` zelf voor
/// waarschuwt. `getExternalStorageDirectory()` geeft `/sdcard/Android/data/<pakket>/files`, en dáár
/// komt na een rit wél een bestand uit dat te lezen valt. Overal elders is dit gewoon [appDir].
String? _logMap;
String get logDir => _logMap ?? appDir;

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

/// Op Windows en macOS is één verschil in schrijfwijze geen ander bestand. Op Linux wel.
bool get padenZijnHoofdletterOngevoelig => Platform.isWindows || Platform.isMacOS;

/// Eén sleutel voor één bestand, ook als de schrijfwijze verschilt.
///
/// **Staat hier omdat het misging toen hij op één plek stond.** [LibraryStore] vouwde zijn levende
/// paden naar kleine letters en gaf ze zo door aan `AlbumUids.prune`, die ze vergeleek met de
/// ONGEVOUWEN sleutels van zijn eigen register. Op een wortel met hoofdletters — `D:\Flac music 2024`
/// — matchte daardoor geen enkel pad, en werd het hele pad→uid-register bij ÉLKE scan leeggegooid.
///
/// Gemeten op 09-08-2026: `album_uids.json` had `"paths":{}` naast 33.826 gemunte uids, en
/// `warm.log` meldde `overgeslagen=228 van 234 albums`. Gevolg: `album_facts.json` was 10 MB die
/// nooit gelezen werd, en elke albumpagina ging opnieuw het net op.
///
/// Wie twee paden vergelijkt vouwt met DEZE functie — beide kanten, altijd.
String padSleutel(String p) => padenZijnHoofdletterOngevoelig ? p.toLowerCase() : p;

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
