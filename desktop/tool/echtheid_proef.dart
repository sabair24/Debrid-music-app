// Meet een map vol muziek door en druk per bestand af wat de echtheidsproef ervan vindt.
//
// Dit draait VOORDAT er ook maar één knop in de app komt. De drempels in echtheid.dart zijn beredeneerd
// en niet gemeten, en deze codebase zet nergens een getal neer dat niet aan echte bestanden is getoetst.
// Wat hier uitkomt bepaalt of `wandDrempelDb = 35` en `laagsteAfkapHz = 14000` blijven staan.
//
// Gebruik:  dart run tool/echtheid_proef.dart "D:\Flac music 2024" [maxAantal] [uitvoerJson]
//
// Met een derde argument schrijft hij de oordelen weg in de vorm die de app leest
// (`echtheid_oordelen.json` in %APPDATA%\DebridMusic). Zo hoeft een eerste meting niet in de app te
// gebeuren en ziet de gebruiker meteen wat er in zijn kast staat.
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_meter.dart';
import 'package:debridmusic/flac_tags.dart';

Future<void> main(List<String> args) async {
  final wortel = args.isEmpty ? r'D:\Flac music 2024' : args.first;
  final max = args.length > 1 ? int.tryParse(args[1]) ?? 100000 : 100000;

  final meter = Echtheidsmeter();
  if (!meter.available) {
    stdout.writeln('ffmpeg niet gevonden — niets te meten');
    return;
  }

  final bestanden = <File>[];
  await for (final e in Directory(wortel).list(recursive: true, followLinks: false)) {
    if (e is File && e.path.toLowerCase().endsWith('.flac')) bestanden.add(e);
    if (bestanden.length >= max) break;
  }
  stdout.writeln('${bestanden.length} FLAC-bestanden');
  stdout.writeln('');

  var nep = 0, onbekend = 0, goed = 0, n = 0;
  final klok = Stopwatch()..start();
  // Zelfde sleutelvorm als echtheid_oordelen.dart: hoofdletterongevoelig op Windows en macOS, één
  // scheidingsteken. Anders vindt de app het oordeel niet terug bij een pad dat net anders is gespeld.
  String sleutel(String p) => (Platform.isWindows || Platform.isMacOS)
      ? p.replaceAll('/', Platform.pathSeparator).replaceAll('\\', Platform.pathSeparator).toLowerCase()
      : p;
  final oordelen = <String, dynamic>{};

  for (final f in bestanden) {
    n++;
    final tags = readFlacTags(f);
    if (tags == null || tags.sampleRate == 0) {
      onbekend++;
      continue;
    }
    final duur = tags.duration?.inSeconds.toDouble() ?? 0;
    final o = await meter.van(f.path,
        kopSampleRate: tags.sampleRate,
        kopBits: tags.bitsPerSample,
        duurSeconden: duur,
        gebruikCache: false);

    final naam = f.path.replaceFirst(wortel, '').replaceAll('\\', '/');
    if (o == null) {
      onbekend++;
      stdout.writeln('?  ${tags.bitsPerSample}/${tags.sampleRate}  niet gemeten   $naam');
      continue;
    }
    oordelen[sleutel(f.path)] = o.toJson();
    final afkap = o.afkapHz == null ? '   -  ' : '${(o.afkapHz! / 1000).toStringAsFixed(1)}k';
    final wand = o.wandDb == null ? ' -  ' : o.wandDb!.toStringAsFixed(0).padLeft(3);
    final merk = o.isNep ? 'NEP' : (o.isOnbekend ? '?  ' : 'ok ');
    if (o.isNep) {
      nep++;
    } else if (o.isOnbekend) {
      onbekend++;
    } else {
      goed++;
    }
    stdout.writeln('$merk ${tags.bitsPerSample}/${tags.sampleRate}  bits=${o.gebruikteBits ?? '-'}  '
        'afkap=$afkap  wand=$wand  vensters=${o.vensters}  $naam');
    if (o.isNep) stdout.writeln('      -> ${waarom(o)}');
  }

  klok.stop();
  if (args.length > 2) {
    final f = File(args[2]);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(oordelen), flush: true);
    stdout.writeln('');
    stdout.writeln('${oordelen.length} oordelen weggeschreven naar ${f.path}');
  }
  stdout.writeln('');
  stdout.writeln('$n onderzocht · $goed in orde · $nep betrapt · $onbekend niet te beoordelen');
  stdout.writeln('${(klok.elapsedMilliseconds / (n == 0 ? 1 : n)).toStringAsFixed(0)} ms per bestand');
}
