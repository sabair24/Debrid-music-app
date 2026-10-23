// De vormen van een albumtitel om de tracklijst op te zoeken (23-10-2026): zonder tracklijst geen achterkant en geen
// cd-afbeelding, en 31 albums vonden er geen omdat hun naam een toevoeging droeg.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/album_facts_resolver.dart' show zoekTitelsVoorFeiten;

void main() {
  test('de gewone titel eerst; daarna zonder " - Single" of " - EP", en zonder ondertitel', () {
    expect(zoekTitelsVoorFeiten('Sailor Song - Single'), ['Sailor Song - Single', 'Sailor Song']);
    expect(zoekTitelsVoorFeiten('Change My World - EP'), ['Change My World - EP', 'Change My World']);
    expect(zoekTitelsVoorFeiten('Parade - Music From The Motion Picture Under The Cherry Moon'),
        ['Parade - Music From The Motion Picture Under The Cherry Moon', 'Parade']);
    expect(zoekTitelsVoorFeiten('Nuttin Nuh Go So (2025 Remaster)'), ['Nuttin Nuh Go So'],
        reason: 'een haakje achteraan ging al weg');
    expect(zoekTitelsVoorFeiten('Brothers in Arms'), ['Brothers in Arms'], reason: 'een gewone titel: één vraag');
    expect(zoekTitelsVoorFeiten('Trip on This (The Remixes)'), ['Trip on This (The Remixes)'],
        reason: 'een haakje dat een andere opname noemt blijft');
  });

  test('aangesloten: de opzoeker probeert de vormen tot er een plaat is', () {
    final r = File('lib/album_facts_resolver.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(r, contains('for (final titel in zoekTitelsVoorFeiten(album.title)) {\n'
        '        groups = await mb.searchReleaseGroups(titel, artist: album.artist);\n'
        '        if (groups.isNotEmpty) break;'));
  });
}
