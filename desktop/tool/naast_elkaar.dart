/// Vindt nummers die TWEE KEER in dezelfde map liggen en laat de beste over.
///
/// Ontstaan doordat een opwaardering naast het origineel landde in plaats van erop: de bestemming werd
/// afgeleid uit de tags van de uploader, en die schrijft geen tracknummer. Zo kwam `Bailamos.flac`
/// naast `10 - Bailamos.flac` te liggen — twee bestanden van hetzelfde nummer, dus twee regels in het
/// album en twee keer dezelfde muziek op schijf.
///
/// [placeFileDetailed] doet dit sinds vandaag niet meer: die krijgt het PAD van het bestaande bestand
/// mee en landt er bovenop. Dit gereedschap is voor wat er al ligt.
///
///     dart run tool/naast_elkaar.dart "D:\Flac music 2024"        # alleen tonen
///     dart run tool/naast_elkaar.dart "D:\Flac music 2024" --doe  # de mindere naar _dubbel
///
/// De verliezer wordt geparkeerd in `_dubbel`, nooit gewist — dezelfde afspraak als de rest van de app.
/// Welke wint beslist [firstIsBetter]: formaat eerst, dan stereo boven surround, dan grootte.
library;

import 'dart:io';

import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/organize.dart';

/// De titel zoals die telt voor "is dit hetzelfde nummer": kleine letters, en alles weg wat per
/// uploader verschilt. Het tracknummer voorop hoort daar nadrukkelijk bij — dat is juist het verschil
/// dat de twee bestanden uit elkaar hield terwijl het om één nummer gaat.
///
/// De VERSIEMARKERS uit de bestandsnaam gaan er wel in, en dat is geen detail. Gemeten geval: in Off
/// The Wall lagen `01 - Don't Stop 'Til You Get Enough.flac` (237 MB) en `01 - ... (single version)
/// .flac` (133 MB). Twee verschillende opnames — maar hun TITLE-tag is bij allebei kaal, want de
/// uploader zette het verschil alleen in de bestandsnaam. Op de tag alleen zou dit gereedschap een
/// opname parkeren die je bewust hebt.
String _sleutel(File f) {
  final naam = f.uri.pathSegments.last.replaceFirst(RegExp(r'\.[^.]+$'), '');
  final titel = (readFlacTags(f)?.title ?? '').trim();
  final basis = titel.isNotEmpty ? titel : naam;
  final kaal = basis
      .replaceFirst(RegExp(r'^\s*\d{1,3}\s*[-.)]?\s*'), '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  final markers = versionMarkers(naam).toList()..sort();
  return markers.isEmpty ? kaal : '$kaal|${markers.join(',')}';
}

/// Duren twee bestanden even lang? Het laatste woord over "is dit dezelfde opname".
///
/// De titel kan kloppen en de versiemarker kan ontbreken terwijl het toch twee takes zijn — een
/// verzamelaar zet geregeld twee mixen van hetzelfde nummer op één plaat. De speelduur verraadt dat
/// wel: die van een remix wijkt seconden tot minuten af. Twee seconden speling voor het verschil
/// tussen rippers.
bool _evenLang(File a, File b) {
  final da = readFlacTags(a)?.duration, db = readFlacTags(b)?.duration;
  if (da == null || db == null) return false; // niet te meten is geen bewijs
  return (da - db).abs() <= const Duration(seconds: 2);
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln('gebruik: dart run tool/naast_elkaar.dart <muziekmap> [--doe]');
    exitCode = 1;
    return;
  }
  final root = Directory(args.first);
  final schrijven = args.contains('--doe');
  if (!root.existsSync()) {
    stdout.writeln('bestaat niet: ${root.path}');
    exitCode = 1;
    return;
  }
  final sep = Platform.pathSeparator;
  final parkeer = Directory('${root.path}$sep$parkeerMap');

  final perMap = <String, List<File>>{};
  for (final e in root.listSync(recursive: true, followLinks: false)) {
    if (e is! File || !e.path.toLowerCase().endsWith('.flac')) continue;
    if (e.path.contains('$sep$parkeerMap$sep') || e.path.contains('${sep}_inkomend$sep')) continue;
    perMap.putIfAbsent(e.parent.path, () => []).add(e);
  }

  var paren = 0, verplaatst = 0;
  for (final entry in perMap.entries) {
    final perTitel = <String, List<File>>{};
    for (final f in entry.value) {
      perTitel.putIfAbsent(_sleutel(f), () => []).add(f);
    }
    for (final groep in perTitel.entries) {
      if (groep.value.length < 2 || groep.key.length < 3) continue;
      // Dezelfde weegschaal als bij het opbergen, zodat de bibliotheek en dit gereedschap nooit een
      // andere kopie de beste kunnen noemen.
      final gesorteerd = [...groep.value]..sort((a, b) => firstIsBetter(a, b) ? -1 : 1);
      final wint = gesorteerd.first;
      // Alleen wat ook even lang duurt telt als dezelfde opname. De rest blijft gewoon staan.
      final weg = gesorteerd.skip(1).where((f) => _evenLang(wint, f)).toList();
      for (final f in gesorteerd.skip(1)) {
        if (weg.contains(f)) continue;
        stdout.writeln('${entry.key.split(sep).last} / ${groep.key}: '
            '${f.uri.pathSegments.last} duurt anders — met rust gelaten');
      }
      if (weg.isEmpty) continue;
      paren++;
      final naam = entry.key.split(sep).last;
      stdout.writeln('$naam / ${groep.key}');
      stdout.writeln('   houden: ${wint.uri.pathSegments.last}  (${_mb(wint)})');
      for (final verliezer in weg) {
        if (!schrijven) {
          stdout.writeln('   zou parkeren: ${verliezer.uri.pathSegments.last}  (${_mb(verliezer)})');
          continue;
        }
        try {
          await parkeer.create(recursive: true);
          var doel = File('${parkeer.path}$sep${verliezer.uri.pathSegments.last}');
          for (var n = 2; doel.existsSync(); n++) {
            doel = File('${parkeer.path}$sep($n) ${verliezer.uri.pathSegments.last}');
          }
          await verliezer.rename(doel.path);
          stdout.writeln('   geparkeerd: ${verliezer.uri.pathSegments.last}  (${_mb(verliezer)})');
          verplaatst++;
        } catch (e) {
          stdout.writeln('   MISLUKT voor ${verliezer.uri.pathSegments.last}: $e');
        }
      }
    }
  }

  stdout.writeln('');
  stdout.writeln('nummers die dubbel in hun eigen map lagen: $paren');
  if (schrijven) {
    stdout.writeln('naar $parkeerMap verplaatst: $verplaatst');
  } else {
    stdout.writeln('niets verplaatst — geef --doe mee om het echt te doen');
  }
}

String _mb(File f) {
  try {
    return '${(f.lengthSync() / 1024 / 1024).toStringAsFixed(0)} MB';
  } catch (_) {
    return '?';
  }
}
