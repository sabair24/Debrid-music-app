/// Wat leest de APP uit dit bestand? Niet wat een ander gereedschap ervan vindt.
///
/// ffprobe toont zijn eigen interne veldnamen (`album_artist`, `track`), en die zeggen niets over de
/// Vorbis-namen die er werkelijk in staan. Alleen de lezer van de app zelf geeft daar antwoord op.
library;

import 'dart:io';

import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/organize.dart';

void main(List<String> args) {
  for (final p in args) {
    final f = File(p);
    if (!f.existsSync()) {
      stdout.writeln('bestaat niet: $p');
      continue;
    }
    stdout.writeln(p.split(Platform.pathSeparator).last);
    final ruw = readFlacRawFields(f);
    for (final e in ruw.entries) {
      if (e.key.toLowerCase().startsWith('replaygain') || e.key.toLowerCase().contains('dynamic')) {
        continue; // meegekomen uit de image; niet waar het hier om gaat
      }
      stdout.writeln('   ruw   ${e.key.padRight(14)} = "${e.value}"');
    }
    final t = readTags(f);
    stdout.writeln('   app   artiest="${t?.artist}"  titel="${t?.title}"  album="${t?.album}"  nr=${t?.trackNo}');
  }
}
