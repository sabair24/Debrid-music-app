// Zinnen die Soulseek weert (Saber, 25-10-2026: "soulseek vindt geen sources niet meer" bij After Hours van The Weeknd).
// Gemeten via de API van de pc: "The Weeknd …" gaf 0 bestanden, "Weeknd …" honderden. Zie geweerde_zinnen.dart.
import 'dart:io';

import 'package:debridmusic/geweerde_zinnen.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('DE KERN: "The Weeknd" wordt "Weeknd" — de artiest blijft in de vraag', () {
    expect(zonderGeweerdeZinnen('The Weeknd Alone Again', kBekendeGeweerdeZinnen), 'Weeknd Alone Again');
    expect(zonderGeweerdeZinnen('the weeknd after hours 24bit', kBekendeGeweerdeZinnen), 'weeknd after hours 24bit');
    expect(zonderGeweerdeZinnen('After Hours The  Weeknd', kBekendeGeweerdeZinnen), 'After Hours Weeknd',
        reason: 'ook achteraan, ook met twee spaties');
  });

  test('DE GRENS: alleen hele woorden, en wat niet geweerd is blijft precies staan', () {
    expect(zonderGeweerdeZinnen('Daft Punk Digital Love', kBekendeGeweerdeZinnen), 'Daft Punk Digital Love');
    expect(zonderGeweerdeZinnen('Theweekndfans mix', kBekendeGeweerdeZinnen), 'Theweekndfans mix');
    expect(zonderGeweerdeZinnen('Weeknd Blinding Lights', kBekendeGeweerdeZinnen), 'Weeknd Blinding Lights');
  });

  test('een staart die zelf geweerd is valt ook weg; blijft er niets over, dan de vraag zoals hij was', () {
    const lijst = {'the weeknd', 'weeknd', 'taylor swift'};
    expect(zonderGeweerdeZinnen('The Weeknd Alone Again', lijst), 'Alone Again',
        reason: 'is ook "weeknd" geweerd, dan rest alleen de titel');
    expect(zonderGeweerdeZinnen('Taylor Swift Shake It Off', lijst), 'Swift Shake It Off');
    expect(zonderGeweerdeZinnen('The Weeknd', {'the weeknd', 'weeknd'}), 'The Weeknd',
        reason: 'een lege vraag heeft niemand iets aan');
    expect(zonderGeweerdeZinnen('Iets', const <String>{}), 'Iets');
  });

  test('ook "The Beatles" (gemeten: 0 met, 5000 zonder)', () {
    expect(zonderGeweerdeZinnen('The Beatles Let It Be', kBekendeGeweerdeZinnen), 'Beatles Let It Be');
    expect(zonderGeweerdeZinnen('The Police Roxanne', kBekendeGeweerdeZinnen), 'The Police Roxanne',
        reason: '"The Police" werkte gewoon');
  });

  test('aangesloten: niets gevonden met "The" vooraan — nog één keer zonder; en meteen leeg is een dode verbinding', () {
    final online = _bron('lib/online.dart');
    expect(online, contains("    final zonderThe = query.trim().replaceFirst(RegExp(r'^the\\s+', caseSensitive: false), '');"));
    expect(online, contains('    if (terugval && laatste.isEmpty && zonderThe != query.trim() && zonderThe.isNotEmpty) {'));
    final s = _bron('lib/soulseek.dart');
    expect(s, contains('    if (uit.isEmpty && _alive && (fout != null || DateTime.now().difference(begon) < kZoekMeteenLeeg)) {'));
    expect(s, contains('const kZoekMeteenLeeg = Duration(milliseconds: 800);'));
  });

  test('aangesloten: bericht 160 van de server vult de lijst, en elke zoekopdracht gaat erlangs', () {
    final s = _bron('lib/soulseek.dart');
    expect(s, contains('        if (code == 160) {'));
    expect(s, contains('            client.geweerdeZinnen\n              ..clear()\n              ..addAll(kBekendeGeweerdeZinnen)'));
    expect(s, contains('        final vraag = zonderGeweerdeZinnen(q, client.geweerdeZinnen);'));
    expect(s, contains('        _conn!.send(_message(26, (_W()..u32(t)..str(vraag)).bytes())); // FileSearch'));
    expect(RegExp(r'_message\(26,').allMatches(s).length, 1, reason: 'één plek waar gezocht wordt');
  });
}
