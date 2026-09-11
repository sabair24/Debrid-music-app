/// Op een tv: de achtergrond tot de rand, de inhoud één keer binnen de marge.
///
/// **Waarom dit bestaat.** Op 11-09-2026 op de Shield: de artiestpagina gebruikte 80% van de breedte,
/// met zwarte banden links en rechts. De marge voor een tv die de rand van het beeld wegsnijdt
/// ([tvOverscan], 48 punten opzij) stond rond de HELE binnennavigator -- dus ook rond de achtergrond
/// van elke pagina -- en de pagina's met een eigen achtergrond namen hem daarbovenop nog eens zelf.
///
/// Nu zit hij per pagina: `_Inzet` geeft hem aan elke gewone pagina en aan de secties, en een
/// [OnderDeBalk]-pagina tekent zelf tot de rand en houdt alleen haar inhoud erbinnen.
///
/// Onderaan ook de metaregel van de albumkop, die rechts afknipte: "2 nummeı".
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late final String hoofd = File('lib/main.dart').readAsStringSync();
  late final String navigatie = File('lib/navigatie.dart').readAsStringSync();

  test('de schil zet geen zijmarge meer rond de hele navigator', () {
    final a = hoofd.indexOf('node: _tvInhoud,');
    final b = hoofd.indexOf('wortel: const _SectieHost()', a);
    expect(a, greaterThan(-1), reason: 'de inhoudsscope van de tv is hernoemd of verdwenen');
    expect(b, greaterThan(a), reason: 'de wortel van de binnennavigator staat er niet meer na');
    expect(hoofd.substring(a, b), isNot(contains('tvOverscan')),
        reason: 'een marge hier houdt ook de achtergrond van elke pagina van de rand weg, en geeft '
            'een pagina met een eigen marge hem twee keer');
  });

  test('_Inzet geeft gewone pagina\'s de zijmarge van de tv', () {
    final a = navigatie.indexOf('class _Inzet');
    expect(a, greaterThan(-1), reason: '_Inzet is hernoemd of verdwenen');
    final lijf = navigatie.substring(a, navigatie.indexOf('\n}\n', a));
    expect(lijf, contains('tvOverscan.left'));
    expect(lijf, contains('tvOverscan.right'));
    expect(lijf, contains('BalkRuimte.van(context)'),
        reason: 'de ruimte onder de zwevende balk blijft gewoon wat hij was');
  });

  test('elke OnderDeBalk-pagina houdt zelf haar inhoud binnen de marge', () {
    // Zelf opgezocht en niet opgesomd: een pagina die er later bij komt, valt hier vanzelf onder --
    // en zonder eigen marge staat haar tekst op een tv straks tegen de rand.
    final paginas = RegExp(r'class (\w+) extends StatefulWidget implements OnderDeBalk')
        .allMatches(hoofd)
        .map((m) => m.group(1)!)
        .toList();
    expect(paginas, isNotEmpty, reason: 'geen enkele OnderDeBalk-pagina gevonden');
    for (final p in paginas) {
      final a = hoofd.indexOf('class _${p}State');
      expect(a, greaterThan(-1), reason: 'de State van $p is niet te vinden');
      final volgende = hoofd.indexOf('\nclass ', a + 10);
      final staat = hoofd.substring(a, volgende < 0 ? hoofd.length : volgende);
      expect(staat, contains('tvOverscan'),
          reason: '$p draagt OnderDeBalk en krijgt de marge dus niet van de navigator; zonder eigen '
              'marge staat haar inhoud op een tv tegen de rand');
    }
  });

  test('de metaregel van de albumkop loopt door in plaats van af te knippen', () {
    final i = hoofd.indexOf('ArtistNames(names: [album.artist], style: const TextStyle(color: _muted)),');
    expect(i, greaterThan(-1), reason: 'de metaregel van de albumkop is verdwenen');
    final ervoor = hoofd.substring(i - 400, i);
    expect(ervoor.lastIndexOf('Wrap('), greaterThan(ervoor.lastIndexOf('Row(')),
        reason: 'een Row knipt artiest · jaar · genre · aantal rechts af zodra het niet past');
  });
}
