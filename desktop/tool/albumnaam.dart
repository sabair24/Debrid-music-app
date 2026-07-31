/// Zet de ALBUM-tag van een of meer bestanden, zonder de rest aan te raken.
///
/// De bibliotheek groepeert op die tag en niet op de map, dus een bestand met een afwijkende
/// albumnaam staat als apart album in beeld — ook al ligt het op de goede plek. Dat gebeurt bij
/// bestanden die vóór de albumnaam-overname binnenkwamen, en bij handmatig verplaatste bestanden.
///
///     dart run tool/albumnaam.dart "Thriller (MFSL One Step)" "pad\naar\nummer.flac" [meer...]
///
/// Gebruikt [writeTagFields] van de app: die herbouwt alléén het tagblok en kopieert elke andere byte,
/// dus de muziek blijft bit voor bit dezelfde. Een omweg via ffmpeg zou het hele bestand hermuxen.
library;

import 'dart:io';

import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/organize.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stdout.writeln('gebruik: dart run tool/albumnaam.dart "<albumnaam>" <bestand> [meer...]');
    exitCode = 1;
    return;
  }
  final naam = args.first;
  for (final pad in args.skip(1)) {
    final f = File(pad);
    if (!f.existsSync()) {
      stdout.writeln('${f.uri.pathSegments.last}: bestaat niet');
      continue;
    }
    final voor = readFlacTags(f)?.album ?? '?';
    final klok = Stopwatch()..start();
    // Rechtstreeks de schrijver, niet via [writeTagFields]: die vangt elke uitzondering af en geeft
    // alleen `false` terug. Bruikbaar in de app, waardeloos als je wilt weten WAAROM het niet lukt.
    bool ok;
    try {
      ok = writeFlacFields(f, {'ALBUM': naam},
          trace: (r) => stdout.writeln('   ${f.uri.pathSegments.last}: $r'));
    } catch (e) {
      stdout.writeln('${f.uri.pathSegments.last}: MISLUKT na ${klok.elapsed.inSeconds}s — $e');
      continue;
    }
    stdout.writeln('${f.uri.pathSegments.last}: "$voor" -> "$naam"  '
        '${ok ? 'ok' : 'GEWEIGERD'} in ${klok.elapsed.inSeconds}s');
  }
}
