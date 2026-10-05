/// De eigen rijen op Start blijven staan zolang je niet op Ververs drukt.
///
/// **Waarom dit bestaat.** Start schudde "Jouw jaren …" en "Lang niet gedraaid" bij elke bouw, en
/// Start bouwt bij elke melding van de bibliotheek — een hoes die binnenkomt, een verrijking die
/// vordert. De rijen sprongen dus door elkaar terwijl je ernaar keek, en de tegel waar je net op
/// wilde tikken stond ineens ergens anders. Gevonden op 05-10-2026, bij "de app moet snel navigeren
/// tussen alle schermen".
library;

import 'dart:io';

import 'package:debridmusic/main.dart';
import 'package:debridmusic/models.dart';
import 'package:flutter_test/flutter_test.dart';

Album _plaat(String artiest, String titel, {String pad = ''}) => Album(titel, artiest, [
      Track(path: pad.isEmpty ? '/m/$artiest/$titel/01.flac' : pad, title: '1', artist: artiest, album: titel),
    ]);

final _platen = [
  for (var i = 0; i < 20; i++) _plaat('Artiest ${i % 7}', 'Plaat $i'),
];

List<String> _namen(List<Album> l) => [for (final a in l) '${a.artist}/${a.title}'];

void main() {
  test('DE KERN: hetzelfde zaad en dezelfde platen geven dezelfde volgorde', () {
    expect(_namen(vastGeschud(_platen, 42)), _namen(vastGeschud(_platen, 42)),
        reason: 'bij elke melding van de bibliotheek sprongen de rijen door elkaar');
  });

  test('DE KERN: ook als de bibliotheek ze in een andere volgorde aanlevert', () {
    // Na een herscan of een nieuwe groepering staat dezelfde kast in een andere volgorde in
    // `lib.albums`; dat is geen reden om de rij om te gooien.
    expect(_namen(vastGeschud(_platen.reversed, 42)), _namen(vastGeschud(_platen, 42)));
  });

  test('DE VAL: een ander zaad — Ververs — geeft een andere volgorde', () {
    expect(_namen(vastGeschud(_platen, 43)), isNot(_namen(vastGeschud(_platen, 42))),
        reason: 'Ververs hoort nog steeds iets anders te laten zien');
    expect(vastGeschud(_platen, 43).toSet(), _platen.toSet(), reason: 'schudden laat niets weg');
  });

  test('DE GRENS: twee platen met dezelfde naam houden ook een vaste volgorde', () {
    final dubbel = [
      _plaat('Oasis', 'Definitely Maybe', pad: '/m/a/01.flac'),
      _plaat('Oasis', 'Definitely Maybe', pad: '/m/b/01.flac'),
      ..._platen,
    ];
    final paden = [for (final a in vastGeschud(dubbel, 7)) a.tracks.first.path];
    final omgekeerd = [for (final a in vastGeschud(dubbel.reversed, 7)) a.tracks.first.path];
    expect(omgekeerd, paden);
    expect(vastGeschud(const <Album>[], 7), isEmpty);
  });

  test('Start schudt zijn eigen rijen niet meer los', () {
    final bron = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final begin = bron.indexOf('final decennium = zwaartepuntDecennium(');
    final eind = bron.indexOf('final anyLoading =', begin);
    expect(begin, isNonNegative);
    expect(eind, greaterThan(begin));
    final stuk = bron.substring(begin, eind);
    expect(stuk, isNot(contains('shuffle(')),
        reason: 'een losse shuffle() in de bouw schudt bij elke melding van de bibliotheek opnieuw');
    expect('vastGeschud('.allMatches(stuk).length, 2, reason: 'beide eigen rijen horen vast geschud');
  });
}
