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

  test('DE KERN: "Madeleine Peyroux" wordt "Peyroux", ook in de jokervorm (21-11-2026)', () {
    // Alle vijf de vragen met haar naam bleven stil, ook "*adeleine Peyroux …"; "Peyroux Smile" gaf 477 bestanden.
    expect(zonderGeweerdeZinnen('Madeleine Peyroux Smile', kBekendeGeweerdeZinnen), 'Peyroux Smile');
    expect(zonderGeweerdeZinnen('*adeleine Peyroux Smile', kBekendeGeweerdeZinnen), 'Peyroux Smile');
    expect(zonderGeweerdeZinnen('Madeleine Peyroux', kBekendeGeweerdeZinnen), 'Peyroux');
    expect(zonderGeweerdeZinnen('*he Weeknd Alone Again', kBekendeGeweerdeZinnen), 'Weeknd Alone Again',
        reason: 'de jokervorm van "The Weeknd" bleef net zo stil');
  });

  test('DE GRENS: de joker alleen vooraan, en wat er niet bij hoort blijft staan', () {
    expect(zonderGeweerdeZinnen('Madeleine Smile', kBekendeGeweerdeZinnen), 'Madeleine Smile');
    expect(zonderGeweerdeZinnen('Peyroux Smile', kBekendeGeweerdeZinnen), 'Peyroux Smile');
    expect(zonderGeweerdeZinnen('Madeleine *eyroux Smile', kBekendeGeweerdeZinnen), 'Madeleine *eyroux Smile',
        reason: 'de joker staat alleen op het eerste woord van de vraag');
    expect(zonderGeweerdeZinnen('*ladeleine Peyroux', kBekendeGeweerdeZinnen), '*ladeleine Peyroux');
  });

  test('aangesloten: twee vragen die na het vervangen gelijk zijn, gaan één keer — en vóór de zoekrem', () {
    final s = _bron('lib/soulseek.dart');
    expect(s, contains('        final vraag = zonderGeweerdeZinnen(q, client.geweerdeZinnen);\n'));
    final lus = s.substring(s.indexOf('      final gevraagd = <String>{};\n      for (final q in queries) {'));
    final dubbel = lus.indexOf('        if (!gevraagd.add(vraag.toLowerCase())) continue;\n');
    expect(dubbel, greaterThan(0));
    expect(dubbel, lessThan(lus.indexOf('await zoekrem.neem(')), reason: 'anders kost hij toch een plek in de zoekrem');
  });

  test('aangesloten: niets gevonden met "The" vooraan — nog één keer zonder; en meteen leeg is een dode verbinding', () {
    final online = _bron('lib/online.dart');
    expect(online, contains("    final zonderThe = query.trim().replaceFirst(RegExp(r'^the\\s+', caseSensitive: false), '');"));
    expect(online, contains('    if (terugval && !telling && !stil && laatste.isEmpty && zonderThe != query.trim() && zonderThe.isNotEmpty) {'));
    final s = _bron('lib/soulseek.dart');
    expect(s, contains('    final sinds = verstuurd ?? begon;\n'
        '    if (uit.isEmpty && _alive && (fout != null || DateTime.now().difference(sinds) < kZoekMeteenLeeg)) {'),
        reason: 'vanaf het versturen: na een wachttijd in de zoekrem werd een dode verbinding anders nooit herkend');
    expect(s, contains('        final nu = verstuurd = DateTime.now();\n'));
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
  // Saber, 23-11-2026: "de app vindt niets van Nicki minaj ???? … Blijft maar draaien ook weer ???". Elke vraag met haar
  // naam bleef stil; "Minaj Starships" gaf 929 bestanden in 1,8 s.
  test('DE KERN: "Nicki Minaj" wordt "Minaj"', () {
    expect(zonderGeweerdeZinnen('Nicki Minaj Starships', kBekendeGeweerdeZinnen), 'Minaj Starships');
    expect(zonderGeweerdeZinnen('nicki minaj', kBekendeGeweerdeZinnen), 'minaj');
    expect(zonderGeweerdeZinnen('Nicki Minaj Pink Friday: Roman Reloaded', kBekendeGeweerdeZinnen),
        'Minaj Pink Friday: Roman Reloaded');
    expect(zonderGeweerdeZinnen('*icki Minaj Starships', kBekendeGeweerdeZinnen), 'Minaj Starships');
  });

  group('zelf leren', () {
    ({String naam, String proefvraag})? proef(String v,
            {Set<String> geweerd = const {}, Set<String> niet = const {}, bool zwijgt = false, int opRij = 0}) =>
        geweerdeNaamProef(v, geweerd: geweerd, nietGeweerd: niet, serverZwijgt: zwijgt, zonderAntwoordOpRij: opRij);

    test('DE KERN: een stille vraag met twee woorden vooraan: één proef zonder het eerste woord', () {
      final p = proef('Charli Xcx Brat');
      expect(p?.naam, 'charli xcx');
      expect(p?.proefvraag, 'Xcx Brat');
      expect(proef('Nicki Minaj', geweerd: {})?.proefvraag, 'Minaj', reason: 'ook de kale naam (de artiestpagina)');
    });

    test('DE GRENS: geen proef als de server zwijgt of net zweeg, bij een bekende of geprobeerde naam, of zonder twee echte woorden',
        () {
      expect(proef('Charli Xcx Brat', zwijgt: true), isNull);
      expect(proef('Charli Xcx Brat', opRij: 1), isNull, reason: 'de vorige vraag bleef ook stil: dat zegt niets over een naam');
      expect(proef('Charli Xcx Brat', geweerd: {'charli xcx'}), isNull);
      expect(proef('Charli Xcx Brat', niet: {'charli xcx'}), isNull, reason: 'niet bij elke stille vraag opnieuw');
      expect(proef('*harli Xcx Brat'), isNull, reason: 'een joker');
      expect(proef('A Xcx Brat'), isNull, reason: 'één letter');
      expect(proef('Twarres'), isNull);
      expect(proef('2024 01 Brat'), isNull, reason: 'geen letters');
    });

    test('bewezen: minstens drie bestanden met de hele naam in hun pad — niet bij een naam die gewoon niemand heeft', () {
      expect(bevatNaam(r'@@x\Nicki_Minaj\Pink Friday\01 Starships.flac', 'nicki minaj'), isTrue);
      expect(bevatNaam(r'@@x\Nicki Minaj - Starships (Explicit).flac', 'nicki minaj'), isTrue);
      expect(bevatNaam(r'@@x\Minaj\Starships.flac', 'nicki minaj'), isFalse);
      expect(bevatNaam(r'@@x\Nickiminaj\Starships.flac', 'nicki minaj'), isFalse, reason: 'hele woorden');
      expect(bevatNaam(r'@@x\Mnicki Minajx\Starships.flac', 'nicki minaj'), isFalse, reason: 'niet binnen een langer woord');
      final nicki = [
        r'@@a\Nicki Minaj\Starships.flac',
        r'@@b\Nicki Minaj - Pink Friday Roman Reloaded\12 Starships.flac',
        r'@@c\nicki.minaj-starships.mp3',
        r'@@d\Starships (Minaj).flac',
      ];
      expect(geweerdBewezen(nicki, 'nicki minaj'), isTrue);
      expect(geweerdBewezen(nicki.take(2), 'nicki minaj'), isFalse, reason: 'twee is niet genoeg');
      expect(geweerdBewezen([r'@@a\Xcx\Brat.flac', r'@@b\Brat Pack\Brat.flac', r'@@c\Brat.mp3'], 'charli xcx'), isFalse,
          reason: 'zonder het eerste woord vond hij iets anders: dat bewijst niets');
      expect(kGeweerdBewijs, 3);
    });

    test('wat geleerd is, blijft na een herstart', () async {
      final map = Directory.systemTemp.createTempSync('dm_geweerd_');
      addTearDown(() => map.deleteSync(recursive: true));
      final a = GeleerdeZinnen('${map.path}/geweerde_zinnen.json');
      expect(await a.laad(), isEmpty);
      await a.voegToe('Charli XCX', DateTime(2026, 11, 23));
      await a.voegToe('charli xcx', DateTime(2026, 11, 24));
      final b = GeleerdeZinnen('${map.path}/geweerde_zinnen.json');
      expect(await b.laad(), {'charli xcx'});
      expect(File('${map.path}/geweerde_zinnen.json').readAsStringSync(), contains('2026-11-23'),
          reason: 'de eerste dag blijft');
    });

    test('aangesloten: de proef vóór de telling van stille vragen, het geleerde overleeft lijst 160, en de pc bewaart het', () {
      final s = _bron('lib/soulseek.dart');
      final stil = s.substring(s.indexOf('    } else if (run.merged.isEmpty && fout == null) {'));
      expect(stil.indexOf('final zonder = await _zonderGeweerdeNaam(queries,'), greaterThan(0));
      expect(stil.indexOf('final zonder = await _zonderGeweerdeNaam(queries,'),
          lessThan(stil.indexOf('client.noteerZoekuitslag(antwoord: false)')),
          reason: 'een geweerde naam is geen zwijgende server');
      expect(s, contains('      if (!proef) {\n        final zonder = await _zonderGeweerdeNaam('));
      expect(s,
          contains('    final uit = await search([p.proefvraag], achtergrond: achtergrond, telling: telling, nogNodig: nogNodig, proef: true);'));
      expect(s, contains('    if (!geweerdBewezen(uit.map((f) => f.filename), p.naam)) {'));
      expect(s, contains('    client.geleerdeZinnen.add(p.naam);\n    client.geweerdeZinnen.add(p.naam);\n'
          '    client.bijGeleerdeZin?.call(p.naam);\n'));
      expect(s, contains('              ..addAll(kBekendeGeweerdeZinnen)\n              ..addAll(client.geleerdeZinnen)\n'));
      final main = _bron('lib/main.dart');
      expect(main, contains("    final geleerd = GeleerdeZinnen('\$appDir\${Platform.pathSeparator}geweerde_zinnen.json');"));
      expect(main, contains('    soulseek.client.bijGeleerdeZin = (naam) => unawaited(geleerd.voegToe(naam, DateTime.now()));'));
    });
  });
}
