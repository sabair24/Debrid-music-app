/// Zet losse tagvelden van een of meer bestanden, zonder de rest aan te raken.
///
/// De bibliotheek groepeert op de TAGS en niet op de map: op ALBUM, op ARTIST, en ze splitst op
/// TRACKTOTAL. Een bestand dat op de goede plek ligt maar één van die velden anders schrijft, staat
/// alsnog als apart album in beeld. Dat gebeurt bij bestanden die vóór de overname-regels binnenkwamen
/// en bij alles wat met de hand verplaatst is.
///
///     dart run tool/albumnaam.dart ALBUM="Thriller (MFSL One Step)" "pad\naar\nummer.flac"
///     dart run tool/albumnaam.dart ARTIST="Enrique Iglesias" TITLE=Escape TRACKTOTAL=16 "pad.flac"
///
/// Gebruikt [writeFlacFields] van de app: die herbouwt alléén het tagblok en kopieert elke andere byte,
/// dus de muziek blijft bit voor bit dezelfde. Een omweg via ffmpeg zou het hele bestand hermuxen.
///
/// Rechtstreeks de schrijver en niet via [writeTagFields]: die vangt elke uitzondering af en geeft
/// alleen `false` terug. Bruikbaar in de app, waardeloos als je wilt weten WAAROM het niet lukt — en
/// dat wilde ik weten toen een schrijfactie faalde omdat de speler het bestand open had.
library;

import 'dart:io';

import 'package:debridmusic/flac_tags.dart';

Future<void> main(List<String> args) async {
  final velden = <String, String?>{};
  final paden = <String>[];
  for (final a in args) {
    final i = a.indexOf('=');
    // Een pad kan ook een '=' bevatten; een veldnaam is hoofdletters en underscores en verder niets.
    if (i > 0 && RegExp(r'^[A-Z_]+$').hasMatch(a.substring(0, i))) {
      velden[a.substring(0, i)] = a.substring(i + 1);
    } else {
      paden.add(a);
    }
  }
  if (velden.isEmpty || paden.isEmpty) {
    stdout.writeln('gebruik: dart run tool/albumnaam.dart VELD=waarde [VELD=waarde ...] <bestand> [meer...]');
    exitCode = 1;
    return;
  }

  for (final pad in paden) {
    final f = File(pad);
    final naam = f.uri.pathSegments.last;
    if (!f.existsSync()) {
      stdout.writeln('$naam: bestaat niet');
      continue;
    }
    final voor = readFlacTags(f);
    final klok = Stopwatch()..start();
    bool ok;
    try {
      ok = writeFlacFields(f, velden, trace: (r) => stdout.writeln('   $naam: $r'));
    } catch (e) {
      stdout.writeln('$naam: MISLUKT na ${klok.elapsed.inSeconds}s — $e');
      continue;
    }
    final na = readFlacTags(f);
    stdout.writeln('$naam: ${ok ? 'ok' : 'GEWEIGERD'} in ${klok.elapsed.inSeconds}s'
        '  album="${voor?.album}"->"${na?.album}"'
        '  artiest="${voor?.artist}"->"${na?.artist}"'
        '  totaal=${voor?.trackTotal}->${na?.trackTotal}');
  }
}
