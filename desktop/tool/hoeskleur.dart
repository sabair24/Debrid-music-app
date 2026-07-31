/// Wat [dominantColour] van een echte hoes maakt.
///
/// Een test met een effen vlak zegt dat de regel klopt; dit zegt wat hij op jouw platen doet. Handig
/// om te zien of een hoes te grijs is voor een was, of juist te fel.
///
///     dart run tool/hoeskleur.dart "pad\naar\hoes.jpg" [meer.jpg ...]
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:debridmusic/artwork.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stdout.writeln('geef een of meer plaatjes mee');
    exitCode = 1;
    return;
  }
  for (final pad in args) {
    final f = File(pad);
    if (!f.existsSync()) {
      stdout.writeln('$pad: bestaat niet');
      continue;
    }
    final c = dominantColour(f.readAsBytesSync());
    if (c == null) {
      stdout.writeln('${f.uri.pathSegments.last}: geen kleur (te grijs, te zwart of te wit)');
      continue;
    }
    final r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF;
    // Dezelfde helderheid als Flutter rekent, zodat je hier ziet hoe donker de gevonden kleur is — en
    // dus waarom de app hem gelijktrekt voordat hij als was wordt gebruikt.
    double kanaal(int v) {
      final x = v / 255;
      return x <= 0.03928 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
    }

    final lum = .2126 * kanaal(r) + .7152 * kanaal(g) + .0722 * kanaal(b);
    stdout.writeln('${f.uri.pathSegments.last}: '
        'rgb($r, $g, $b)  #${c.toRadixString(16).substring(2)}  '
        'helderheid ${lum.toStringAsFixed(2)}'
        '${lum < .06 ? '  ← te donker om zo te gebruiken; de app trekt de helderheid gelijk' : ''}');
  }
}
