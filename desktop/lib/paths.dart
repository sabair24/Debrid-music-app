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
  // Vóór er ook maar iets gelezen wordt, en alleen de allereerste keer. Zie [verhuisMap].
  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      try {
        await verhuisMap(Directory(sandboxPad(home)), Directory(_resolved!));
      } catch (_) {/* niet kunnen verhuizen is vervelend, geen reden om niet te starten */}
    }
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

/// De bundel-id, zoals hij in `Info.plist` staat.
///
/// Hier met de hand en niet uit `PackageInfo`: dit draait vóór alles, en `PackageInfo` heeft de
/// bindings van Flutter nodig die op dat moment nog niet staan. Verandert de id ooit, dan verandert
/// ook de map hieronder en is er niets te verhuizen -- dat is dan geen fout maar een nieuwe app.
const _bundelId = 'com.debridmedia.music';

/// Waar de gegevens stonden toen de Mac-app nog in de sandbox draaide.
///
/// De sandbox is er in augustus 2026 afgehaald, omdat een app erbinnen zichzelf niet kan bijwerken:
/// hij mag niet buiten zijn eigen container schrijven, en een script dat hij start erft die
/// beperking. Zonder sandbox wijst `getApplicationSupportDirectory` naar een heel andere map, dus
/// zonder de verhuizing hieronder zou de app opkomen alsof hij nooit gekoppeld was.
String sandboxPad(String home) =>
    '$home/Library/Containers/$_bundelId/Data/Library/Application Support/$_bundelId/DebridMusic';

/// Zet de oude map op de nieuwe plek, precies één keer. Teruggave: is er iets verhuisd?
///
/// **Hernoemen en niet kopiëren.** Het gaat om zo'n tweehonderd megabyte, waarvan het meeste hoezen
/// zijn; kopiëren is een merkbare pauze bij het opstarten en kan halverwege afbreken. Allebei de
/// mappen staan op dezelfde schijf, dus hernoemen kost geen tijd en gebeurt in één keer of niet.
///
/// Er wordt NOOIT over bestaande gegevens heen gegaan. Staat er al iets op de nieuwe plek, dan is
/// die app daar al eens geweest en is de oude map hooguit een echo van vroeger.
Future<bool> verhuisMap(Directory oud, Directory nieuw) async {
  if (!await oud.exists()) return false;
  if (await nieuw.exists()) {
    // Een lege map is geen gegevens -- die kan van een eerdere start zijn die halverwege stopte, en
    // zou de verhuizing anders voorgoed blokkeren.
    if (!await nieuw.list().isEmpty) return false;
    await nieuw.delete();
  }
  await nieuw.parent.create(recursive: true);
  await oud.rename(nieuw.path);
  return true;
}

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

/// De map waarin de torrentmotor werkt, onder de downloadmap.
///
/// **Waarom hij een eigen naam heeft, en waarom die hier staat.** De scanner leest de hele
/// muziekmap en sloeg alleen `_inkomend` en de parkeermap over. Alles wat aria2 aan het binnenhalen
/// was — halve bestanden, en bestanden die hij opnieuw ophaalde omdat een eerdere download ze had
/// weggehaald — kwam dus gewoon in de bibliotheek terecht. Dat is de klacht van 29-08-2026: "bij het
/// kiezen komen er liedjes bij die ik nooit heb aangeklikt".
///
/// Eén naam, twee plekken: `online.dart` maakt hem, `library.dart` slaat hem over. Zouden die twee
/// uiteenlopen, dan is het gevolg precies dezelfde stilte als hiervoor — vandaar dat hij hier staat,
/// in het bestand dat ze allebei al kennen.
const torrentWerkMap = '_torrentwerk';
