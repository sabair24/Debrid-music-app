/// De reserve als Debrid Music op de Shield niet antwoordt: de pc wekt hem via netwerk-adb en start de app (Saber,
/// 31-10-2026: "Wekken, en dan via adb starten").
///
/// Normaal is dit niet nodig: de dienst op de Shield (`Ontvanger.kt`) houdt de app vindbaar, ook in de slaap, na een
/// herstart en na een update. Dit vangt op wat daarbuiten valt — de app gesloten met "Stop geforceerd", of Android die
/// hem toch opruimde. Chromecast kan dat niet: die start alleen apps die bij Google als Cast-app geregistreerd zijn.
///
/// Alleen op de pc, en alleen als adb er staat (de Android SDK) en netwerk-adb op de Shield aan staat (ontwikkelaarsopties
/// › netwerkfoutopsporing). De sleutel van deze pc is daar al eens toegestaan; zonder die toestemming weigert de Shield,
/// en dan zegt de zone gewoon "niet bereikbaar", zoals voorheen.
library;

import 'dart:async';
import 'dart:io';

/// Waar adb op deze pc staat, of null. Eerst de Android SDK (zoals Android Studio hem neerzet), dan de omgeving.
String? zoekAdb({Map<String, String>? omgeving, bool Function(String pad)? bestaat}) {
  final env = omgeving ?? Platform.environment;
  final staat = bestaat ?? (p) => File(p).existsSync();
  final sep = Platform.pathSeparator;
  final naam = Platform.isWindows ? 'adb.exe' : 'adb';
  final wortels = [
    env['ANDROID_HOME'],
    env['ANDROID_SDK_ROOT'],
    if (env['LOCALAPPDATA'] case final l?) '$l${sep}Android${sep}Sdk',
    if (env['HOME'] case final h?) '$h${sep}Library${sep}Android${sep}sdk',
  ];
  for (final w in wortels) {
    if (w == null || w.isEmpty) continue;
    final pad = '$w${sep}platform-tools$sep$naam';
    if (staat(pad)) return pad;
  }
  return null;
}

/// De opdracht op de Shield: wakker (de tv gaat via CEC mee aan) en Debrid Music vooraan, met de startopdracht van de
/// launcher — zo komt een bestaande taak naar voren in plaats van een tweede venster.
const kAdbWekOpdracht = 'input keyevent KEYCODE_WAKEUP; '
    'am start -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER '
    '-n com.debridmusic.app/.MainActivity';

/// Wek het toestel op [adres] en start Debrid Music. Waar als adb het aannam (de app start dan; of hij weer verbindt,
/// ziet de aanroeper aan de zonelijn).
Future<bool> wekViaAdb(
  String adres, {
  required String adb,
  Future<ProcessResult> Function(String programma, List<String> argumenten)? draai,
  void Function(String)? log,
}) async {
  final doe = draai ?? (p, a) => Process.run(p, a);
  final doel = '$adres:5555';
  try {
    final verbind = await doe(adb, ['connect', doel]).timeout(const Duration(seconds: 8));
    final uit = '${verbind.stdout}'.trim();
    // "connected to …" of "already connected to …"; "failed to connect" / "unable to connect" is nee.
    if (verbind.exitCode != 0 || !uit.contains('connected to') || uit.contains('failed') || uit.contains('unable')) {
      log?.call('adb: kon $doel niet bereiken ($uit)');
      return false;
    }
    final start = await doe(adb, ['-s', doel, 'shell', kAdbWekOpdracht]).timeout(const Duration(seconds: 10));
    final antwoord = '${start.stdout}${start.stderr}'.trim();
    // Niet toegestaan ("device unauthorized") geeft een foutcode; `am start` zonder de app zegt "Error: …" met code 0.
    if (start.exitCode != 0 || antwoord.contains('Error')) {
      log?.call('adb: wekken/starten op $doel mislukt ($antwoord)');
      return false;
    }
    log?.call('adb: $doel gewekt, Debrid Music gestart');
    return true;
  } catch (e) {
    log?.call('adb: $doel — $e');
    return false;
  }
}
