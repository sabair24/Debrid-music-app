/// Een cd-in-één-FLAC opknippen in losse getagde nummers, volgens zijn cue.
///
/// De vier Thunderdome-images in de wortel van de bibliotheek zijn EAC-rips: één FLAC van ruim een
/// uur met een cue ernaast die per nummer de titel, de artiest en het startpunt geeft. Zo staan ze
/// als vier nummers van een uur in de bibliotheek, en kun je niet naar een nummer springen.
///
/// Knipt met ffmpeg en codeert opnieuw. Dat is verliesloos -- FLAC in, FLAC uit -- maar het is geen
/// bytes-kopie: op een willekeurig punk kappen kan niet zonder de frames te hercoderen.
///
/// Raakt het originele bestand nooit aan. De cue en de image blijven staan tot de gebruiker zegt dat
/// het goed is; opruimen is een aparte, omkeerbare stap.
///
///     dart run tool/cue_splitsen.dart <ffmpeg.exe> "<cue>" "<doelwortel>"
///     dart run tool/cue_splitsen.dart ... --doen
library;

import 'dart:io';

import 'package:debridmusic/organize.dart' show safeSeg;

/// Eén nummer uit de cue.
class Nummer {
  Nummer(this.no);
  final int no;
  String titel = '', artiest = '';
  double start = 0;
}

/// `mm:ss:ff` waarin ff frames van een vijfenzeventigste seconde zijn -- de eenheid van een cd, niet
/// van video. mm kan boven 59 uitkomen; het zijn minuten, geen klok.
double _tijd(String s) {
  final d = s.split(':');
  if (d.length != 3) return 0;
  final m = int.tryParse(d[0]) ?? 0, sec = int.tryParse(d[1]) ?? 0, fr = int.tryParse(d[2]) ?? 0;
  return m * 60 + sec + fr / 75.0;
}

String _tussen(String regel, String woord) {
  final i = regel.indexOf(woord);
  if (i < 0) return '';
  var rest = regel.substring(i + woord.length).trim();
  if (rest.startsWith('"')) {
    final eind = rest.indexOf('"', 1);
    if (eind > 0) return rest.substring(1, eind);
  }
  return rest;
}

void main(List<String> args) async {
  final echt = args.contains('--doen');
  final p = args.where((a) => !a.startsWith('--')).toList();
  if (p.length < 3) {
    stderr.writeln('gebruik: <ffmpeg.exe> "<cue>" "<doelwortel>" [--doen]');
    exit(1);
  }
  final ffmpeg = p[0];
  final cue = File(p[1]);
  final wortel = p[2];
  if (!cue.existsSync()) {
    stderr.writeln('geen cue: ${p[1]}');
    exit(1);
  }

  var album = '', albumArtiest = '', jaar = '', genre = '', bestand = '';
  final nummers = <Nummer>[];
  for (final regel in cue.readAsLinesSync()) {
    final t = regel.trim();
    if (t.startsWith('TRACK ')) {
      nummers.add(Nummer(int.tryParse(t.split(RegExp(r'\s+'))[1]) ?? nummers.length + 1));
    } else if (t.startsWith('TITLE')) {
      final v = _tussen(t, 'TITLE');
      if (nummers.isEmpty) {
        album = v;
      } else {
        nummers.last.titel = v;
      }
    } else if (t.startsWith('PERFORMER')) {
      final v = _tussen(t, 'PERFORMER');
      if (nummers.isEmpty) {
        albumArtiest = v;
      } else {
        nummers.last.artiest = v;
      }
    } else if (t.startsWith('FILE')) {
      bestand = _tussen(t, 'FILE');
    } else if (t.startsWith('REM DATE')) {
      jaar = _tussen(t, 'REM DATE');
    } else if (t.startsWith('REM GENRE')) {
      genre = _tussen(t, 'REM GENRE');
    } else if (t.startsWith('INDEX 01') && nummers.isNotEmpty) {
      nummers.last.start = _tijd(t.split(RegExp(r'\s+')).last);
    }
  }

  final bron = File('${cue.parent.path}${Platform.pathSeparator}$bestand');
  if (!bron.existsSync()) {
    stderr.writeln('de cue wijst naar "$bestand", en die staat er niet');
    exit(1);
  }
  // Een verzamelaar hoort onder één naam te staan en niet onder elke gastartiest.
  final verzamelaar = RegExp(r'^(various|va)\b', caseSensitive: false).hasMatch(albumArtiest);
  final mapArtiest = verzamelaar ? 'Various Artists' : albumArtiest;
  final doelMap = Directory(
      '$wortel${Platform.pathSeparator}${safeSeg(mapArtiest)}${Platform.pathSeparator}${safeSeg(album)}');

  stdout.writeln('album      : $album');
  stdout.writeln('artiest    : $mapArtiest   jaar: $jaar   genre: $genre');
  stdout.writeln('bron       : ${bron.path.split(Platform.pathSeparator).last}'
      '  (${(bron.lengthSync() / 1024 / 1024).round()} MB)');
  stdout.writeln('doel       : ${doelMap.path}');
  stdout.writeln('nummers    : ${nummers.length}');

  if (!echt) {
    for (final n in nummers) {
      final eind = nummers.indexOf(n) + 1 < nummers.length ? nummers[nummers.indexOf(n) + 1].start : null;
      final duur = eind == null ? null : eind - n.start;
      stdout.writeln('  ${n.no.toString().padLeft(2, '0')}  ${n.start.toStringAsFixed(2).padLeft(8)}s'
          '  ${duur == null ? "tot einde" : "${duur.toStringAsFixed(2)}s"}  ${n.artiest} — ${n.titel}');
    }
    stdout.writeln('\nproefloop — niets geschreven');
    return;
  }

  doelMap.createSync(recursive: true);
  var gedaan = 0;
  for (var i = 0; i < nummers.length; i++) {
    final n = nummers[i];
    final duur = i + 1 < nummers.length ? nummers[i + 1].start - n.start : null;
    final naam = safeSeg('${n.no.toString().padLeft(2, '0')} - ${n.artiest} - ${n.titel}.flac');
    final uit = File('${doelMap.path}${Platform.pathSeparator}$naam');
    if (uit.existsSync()) {
      stdout.writeln('  staat er al, overgeslagen: $naam');
      continue;
    }
    final argumenten = <String>[
      '-hide_banner', '-loglevel', 'error', '-nostdin',
      // Zoeken vóór -i, want anders wordt elk nummer vanaf het begin van de cd gedecodeerd en duurt
      // één cd een kwartier in plaats van een minuut. FLAC is framegebaseerd, dus dit zoekt exact.
      '-ss', n.start.toStringAsFixed(6),
      if (duur != null) ...['-t', duur.toStringAsFixed(6)],
      '-i', bron.path,
      '-c:a', 'flac', '-compression_level', '8',
      '-metadata', 'TITLE=${n.titel}',
      // Op een verzamelaar gaat de ARTIEST-tag naar de verzamelnaam en de echte uitvoerder naar
      // PERFORMER. Dat is geen smaakkwestie maar de conventie van deze app: albums worden gegroepeerd
      // op artiest plus albumtitel, dus met per nummer een andere artiest valt één cd uiteen in
      // tweeëntwintig albums van één nummer. Gemeten: 84 nummers gaven 76 losse "albums".
      //
      // De uitvoerder gaat nergens verloren -- hij staat in PERFORMER en in de bestandsnaam, precies
      // waar relativePathFor hem voor een compilatie ook zet.
      '-metadata', verzamelaar ? 'ARTIST=$mapArtiest' : 'ARTIST=${n.artiest}',
      if (verzamelaar) ...['-metadata', 'PERFORMER=${n.artiest}'],
      '-metadata', 'ALBUM=$album',
      '-metadata', 'ALBUMARTIST=$mapArtiest',
      '-metadata', 'TRACKNUMBER=${n.no}',
      '-metadata', 'TRACKTOTAL=${nummers.length}',
      if (jaar.isNotEmpty) ...['-metadata', 'DATE=$jaar'],
      if (genre.isNotEmpty) ...['-metadata', 'GENRE=$genre'],
      uit.path,
    ];
    final r = await Process.run(ffmpeg, argumenten);
    if (r.exitCode != 0) {
      stderr.writeln('  MISLUKT ${n.no}: ${r.stderr}');
      continue;
    }
    gedaan++;
    stdout.writeln('  ${n.no.toString().padLeft(2, '0')}  '
        '${(uit.lengthSync() / 1024 / 1024).toStringAsFixed(1).padLeft(5)} MB  $naam');
  }
  stdout.writeln('\n$gedaan van ${nummers.length} geschreven');
}
