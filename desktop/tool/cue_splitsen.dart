/// Een cd-in-één-FLAC opknippen in losse getagde nummers, volgens zijn cue.
///
/// De vier Thunderdome-images in de wortel van de bibliotheek zijn EAC-rips: één FLAC van ruim een
/// uur met een cue ernaast die per nummer de titel, de artiest en het startpunt geeft. Zo staan ze
/// als vier nummers van een uur in de bibliotheek, en kun je niet naar een nummer springen.
///
/// Knipt met ffmpeg en codeert opnieuw. Dat is verliesloos -- FLAC in, FLAC uit -- maar het is geen
/// bytes-kopie: op een willekeurig punt kappen kan niet zonder de frames te hercoderen.
///
/// MEERDERE cues achter elkaar worden als één plaat behandeld: één albummap, en de nummers lopen
/// DOOR. Dat is niet zomaar een keuze maar de conventie van deze app -- zie trackNoFromPosition in
/// organize.dart, dat een positie op een dubbelalbum omzet in "het nummer waar een luisteraar naartoe
/// zou tellen". Het model kent geen schijfbegrip, dus vier keer een "nummer 1" zou botsen.
/// DISCNUMBER wordt wel meegeschreven, voor spelers die er iets mee doen.
///
/// Raakt de bronbestanden nooit aan.
///
///     dart run tool/cue_splitsen.dart <ffmpeg.exe> "<doelwortel>" "<cue1>" "<cue2>" … [--doen]
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

/// Alles wat één cue over zijn schijf zegt.
class Schijf {
  String album = '', albumArtiest = '', jaar = '', genre = '', bestand = '';
  final nummers = <Nummer>[];
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
  final rest = regel.substring(i + woord.length).trim();
  if (rest.startsWith('"')) {
    final eind = rest.indexOf('"', 1);
    if (eind > 0) return rest.substring(1, eind);
  }
  return rest;
}

Schijf _lees(File cue) {
  final s = Schijf();
  for (final regel in cue.readAsLinesSync()) {
    final t = regel.trim();
    if (t.startsWith('TRACK ')) {
      s.nummers.add(Nummer(int.tryParse(t.split(RegExp(r'\s+'))[1]) ?? s.nummers.length + 1));
    } else if (t.startsWith('TITLE')) {
      final v = _tussen(t, 'TITLE');
      if (s.nummers.isEmpty) {
        s.album = v;
      } else {
        s.nummers.last.titel = v;
      }
    } else if (t.startsWith('PERFORMER')) {
      final v = _tussen(t, 'PERFORMER');
      if (s.nummers.isEmpty) {
        s.albumArtiest = v;
      } else {
        s.nummers.last.artiest = v;
      }
    } else if (t.startsWith('FILE')) {
      s.bestand = _tussen(t, 'FILE');
    } else if (t.startsWith('REM DATE')) {
      s.jaar = _tussen(t, 'REM DATE');
    } else if (t.startsWith('REM GENRE')) {
      s.genre = _tussen(t, 'REM GENRE');
    } else if (t.startsWith('INDEX 01') && s.nummers.isNotEmpty) {
      s.nummers.last.start = _tijd(t.split(RegExp(r'\s+')).last);
    }
  }
  return s;
}

/// "Thunderdome … Collection (CD1)" -> "Thunderdome … Collection". Alleen als er meer dan één schijf
/// is: bij een losse cd is dat achtervoegsel de naam van de plaat en hoort het te blijven staan.
String _zonderSchijf(String album) =>
    album.replaceAll(RegExp(r'\s*[({\[]?\s*(cd|disc|disk)\s*\d+\s*[)}\]]?\s*$', caseSensitive: false), '').trim();

void main(List<String> args) async {
  final echt = args.contains('--doen');
  final p = args.where((a) => !a.startsWith('--')).toList();
  if (p.length < 3) {
    stderr.writeln('gebruik: <ffmpeg.exe> "<doelwortel>" "<cue1>" ["<cue2>" …] [--doen]');
    exit(1);
  }
  final ffmpeg = p[0];
  final wortel = p[1];
  final cues = p.skip(2).map(File.new).toList();
  for (final c in cues) {
    if (!c.existsSync()) {
      stderr.writeln('geen cue: ${c.path}');
      exit(1);
    }
  }

  final schijven = cues.map(_lees).toList();
  final eerste = schijven.first;
  final meerdere = schijven.length > 1;
  final album = meerdere ? _zonderSchijf(eerste.album) : eerste.album;
  // Een verzamelaar hoort onder één naam te staan en niet onder elke gastartiest.
  final verzamelaar =
      RegExp(r'^(various|va)\b', caseSensitive: false).hasMatch(eerste.albumArtiest);
  final mapArtiest = verzamelaar ? 'Various Artists' : eerste.albumArtiest;
  final totaal = schijven.fold<int>(0, (n, s) => n + s.nummers.length);
  final doelMap = Directory(
      '$wortel${Platform.pathSeparator}${safeSeg(mapArtiest)}${Platform.pathSeparator}${safeSeg(album)}');

  stdout.writeln('album   : $album');
  stdout.writeln('artiest : $mapArtiest   jaar: ${eerste.jaar}   genre: ${eerste.genre}');
  stdout.writeln('schijven: ${schijven.length}   nummers: $totaal (doorlopend genummerd)');
  stdout.writeln('doel    : ${doelMap.path}');

  if (!echt) {
    var n = 0;
    for (var d = 0; d < schijven.length; d++) {
      for (final t in schijven[d].nummers) {
        n++;
        stdout.writeln('  ${n.toString().padLeft(2, '0')}  cd${d + 1}-${t.no.toString().padLeft(2, '0')}'
            '  ${t.artiest} — ${t.titel}');
      }
    }
    stdout.writeln('\nproefloop — niets geschreven');
    return;
  }

  doelMap.createSync(recursive: true);
  var doorlopend = 0, gedaan = 0;
  for (var d = 0; d < schijven.length; d++) {
    final s = schijven[d];
    final bron = File('${cues[d].parent.path}${Platform.pathSeparator}${s.bestand}');
    if (!bron.existsSync()) {
      stderr.writeln('de cue wijst naar "${s.bestand}", en die staat er niet');
      continue;
    }
    for (var i = 0; i < s.nummers.length; i++) {
      final t = s.nummers[i];
      doorlopend++;
      final duur = i + 1 < s.nummers.length ? s.nummers[i + 1].start - t.start : null;
      final naam = safeSeg('${doorlopend.toString().padLeft(2, '0')} - ${t.artiest} - ${t.titel}.flac');
      final uit = File('${doelMap.path}${Platform.pathSeparator}$naam');
      if (uit.existsSync()) {
        stdout.writeln('  staat er al, overgeslagen: $naam');
        continue;
      }
      final argumenten = <String>[
        '-hide_banner', '-loglevel', 'error', '-nostdin',
        // Zoeken vóór -i, want anders wordt elk nummer vanaf het begin van de cd gedecodeerd en duurt
        // één cd een kwartier in plaats van een minuut. FLAC is framegebaseerd, dus dit zoekt exact.
        '-ss', t.start.toStringAsFixed(6),
        if (duur != null) ...['-t', duur.toStringAsFixed(6)],
        '-i', bron.path,
        '-c:a', 'flac', '-compression_level', '8',
        '-metadata', 'TITLE=${t.titel}',
        // Op een verzamelaar gaat ARTIST naar de verzamelnaam en de echte uitvoerder naar PERFORMER.
        // Geen smaakkwestie: albums worden gegroepeerd op artiest plus albumtitel, dus met per nummer
        // een andere artiest valt één cd uiteen in tweeëntwintig albums van één nummer. Gemeten: 84
        // nummers gaven 76 losse "albums". De uitvoerder gaat nergens verloren -- hij staat in
        // PERFORMER en in de bestandsnaam, precies waar relativePathFor hem ook zet.
        '-metadata', verzamelaar ? 'ARTIST=$mapArtiest' : 'ARTIST=${t.artiest}',
        if (verzamelaar) ...['-metadata', 'PERFORMER=${t.artiest}'],
        '-metadata', 'ALBUM=$album',
        '-metadata', 'ALBUMARTIST=$mapArtiest',
        '-metadata', 'TRACKNUMBER=$doorlopend',
        '-metadata', 'TRACKTOTAL=$totaal',
        if (meerdere) ...['-metadata', 'DISCNUMBER=${d + 1}', '-metadata', 'DISCTOTAL=${schijven.length}'],
        if (s.jaar.isNotEmpty) ...['-metadata', 'DATE=${s.jaar}'],
        if (s.genre.isNotEmpty) ...['-metadata', 'GENRE=${s.genre}'],
        uit.path,
      ];
      final r = await Process.run(ffmpeg, argumenten);
      if (r.exitCode != 0) {
        stderr.writeln('  MISLUKT $doorlopend: ${r.stderr}');
        continue;
      }
      gedaan++;
    }
    stdout.writeln('  cd${d + 1}: ${s.nummers.length} nummers, tot en met $doorlopend');
  }
  stdout.writeln('\n$gedaan van $totaal geschreven');
}
