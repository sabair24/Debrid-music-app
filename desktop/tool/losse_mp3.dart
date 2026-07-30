/// De tags van één mp3 opschonen die van een warez-site komt.
///
/// Wat er in stond: artiest, titel en album met onderstrepingstekens waar spaties horen, en drie
/// velden -- albumartiest, jaar en tracknummer -- die allemaal "WWW.CLUB-BOX.COM" bevatten. Een jaar
/// en een tracknummer die een webadres zijn, zijn erger dan leeg: ze sorteren verkeerd en een
/// albumartiest die reclame is, zet de plaat onder een verzonnen naam in de bibliotheek.
///
/// AcoustID kent het nummer niet -- score 0,72 en nul opnames, wat je bij een bootleg verwacht -- dus
/// er valt niets op te halen. Alles wat hier gebeurt komt uit het bestand zelf.
///
///     dart run tool/losse_mp3.dart "<pad>"            (alleen lezen)
///     dart run tool/losse_mp3.dart "<pad>" --doen     (schrijven)
library;

import 'dart:io';

import 'package:debridmusic/mp3_tags.dart';

/// Reclame die als tagwaarde is binnengeslopen. Bewust een lijst met precieze waarden en geen
/// slimme regel: iets wat "verdacht" heet en zelf beslist, gooit ooit een echte titel weg.
bool _isReclame(String? v) {
  final s = (v ?? '').trim().toLowerCase();
  return s.contains('www.') || s.contains('.com') || s.contains('http');
}

String _spaties(String s) => s.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

void main(List<String> args) {
  final echt = args.contains('--doen');
  final paden = args.where((a) => !a.startsWith('--')).toList();
  if (paden.isEmpty) {
    stderr.writeln('geef een pad');
    exit(1);
  }
  final f = File(paden.first);
  if (!f.existsSync()) {
    stderr.writeln('bestaat niet: ${paden.first}');
    exit(1);
  }

  final nu = readMp3RawFields(f);
  stdout.writeln('wat er NU in staat:');
  if (nu.isEmpty) stdout.writeln('   — niets —');
  nu.forEach((k, v) => stdout.writeln('   ${k.padRight(12)} = "$v"'));

  final artiest = _spaties(nu['artist'] ?? '');
  final titel = _spaties(nu['title'] ?? '');
  final album = _spaties(nu['album'] ?? '');

  final velden = <String, String?>{};
  if (artiest.isNotEmpty && artiest != nu['artist']) velden['ARTIST'] = artiest;
  if (titel.isNotEmpty && titel != nu['title']) velden['TITLE'] = titel;
  if (album.isNotEmpty && album != nu['album']) velden['ALBUM'] = album;
  // De albumartiest krijgt de artiest in plaats van de reclame: leeg laten zou de plaat onder
  // "Onbekende artiest" zetten, en dat is niet beter.
  if (_isReclame(nu['albumartist']) && artiest.isNotEmpty) velden['ALBUMARTIST'] = artiest;
  // Jaar en tracknummer krijgen niets: een webadres is geen getal, en er is geen echte waarde bekend.
  if (_isReclame(nu['date'])) velden['DATE'] = '';
  if (_isReclame(nu['tracknumber'])) velden['TRACKNUMBER'] = '';

  stdout.writeln('\nwat er anders wordt:');
  if (velden.isEmpty) stdout.writeln('   — niets, het staat al goed —');
  velden.forEach((k, v) => stdout.writeln('   ${k.padRight(12)} -> ${v!.isEmpty ? "(leeggemaakt)" : '"$v"'}'));

  if (!echt || velden.isEmpty) {
    if (!echt) stdout.writeln('\nproefloop — niets geschreven');
    return;
  }
  writeMp3Fields(f, velden, trace: stdout.writeln);
  stdout.writeln('\nvan schijf teruggelezen:');
  readMp3RawFields(f).forEach((k, v) => stdout.writeln('   ${k.padRight(12)} = "$v"'));
}
