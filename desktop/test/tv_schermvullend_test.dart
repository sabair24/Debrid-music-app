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

  // De tweede ronde, dezelfde dag. Na de eerste reparatie liep de achtergrond van de artiestpagina
  // wel tot de rand, maar de FOTO van de kop niet: die stond binnen een SafeArea met de hele
  // tv-marge, en hield 48 punten voor de rand op met een strook van de achtergrond ernaast.
  test('de foto van de artiestkop loopt tot de rand, de inhoud blijft binnen de marge', () {
    final a = hoofd.indexOf('class _ArtistBrowsePageState');
    expect(a, greaterThan(-1), reason: 'de State van ArtistBrowsePage is niet te vinden');
    final e = hoofd.indexOf('\nclass ', a + 10);
    final staat = hoofd.substring(a, e < 0 ? hoofd.length : e);
    expect(staat, isNot(contains('minimum: tvOverscan,')),
        reason: 'de hele marge op de SafeArea houdt ook de foto van de kop van de rand weg');
    expect(staat, contains('minimum: EdgeInsets.only(top: tvOverscan.top)'),
        reason: 'de bovenkant van de marge blijft: daar snijdt een tv net zo goed weg');
    final g = staat.indexOf('SliverMainAxisGroup(');
    expect(g, greaterThan(-1), reason: 'de inhoud onder de kop staat niet meer in één groep');
    expect(staat.substring(g - 200, g), contains('EdgeInsets.symmetric(horizontal: tvOverscan.left)'),
        reason: 'zonder zijmarge op de groep staan de lijsten op een tv tegen de rand');
    expect(staat, contains('10 + tvOverscan.left'),
        reason: 'de terugpijl hoort binnen de marge, ook al loopt de kop erachter tot de rand');

    final k = hoofd.indexOf('class EditorialeKop ');
    expect(k, greaterThan(-1), reason: 'EditorialeKop is hernoemd of verdwenen');
    final kop = hoofd.substring(k, hoofd.indexOf('\nclass ', k + 10));
    expect(kop, contains('+ tvOverscan.left'),
        reason: 'de naam en de feiten in de kop horen binnen wat een tv laat zien');
  });

  test('de metaregel van een online album knipt niet meer af', () {
    final a = hoofd.indexOf('class _AlbumBrowsePageState');
    expect(a, greaterThan(-1), reason: 'de State van AlbumBrowsePage is niet te vinden');
    final e = hoofd.indexOf('\nclass ', a + 10);
    final staat = hoofd.substring(a, e < 0 ? hoofd.length : e);
    final w = staat.indexOf('_maybeFocusable(Wrap(');
    expect(w, greaterThan(-1),
        reason: 'een Row met een beletselteken knipt artiest · jaar · aantal af zodra het niet past');
    expect(staat.substring(w, w + 300), contains('names: [widget.artistName]'));
    expect(staat, contains("_tracks.length == 1 ? 'nummer' : 'nummers'"),
        reason: '"1 nummers" is geen Nederlands');
  });
}
