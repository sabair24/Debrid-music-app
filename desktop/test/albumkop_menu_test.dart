// De kop van een albumpagina: terug, boekje en ⋯ (Saber, 16-10-2026). Er stonden tot negen ronde knoppen
// over de hoes; de acties zitten nu in een menu, met dezelfde voorwaarden.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
  final begin = main.indexOf('class _AlbumDetailPageState');
  final eind = main.indexOf('\n// ── ', begin + 1);
  final pagina = main.substring(begin, eind < 0 ? main.length : eind);

  String balk() {
    final a = pagina.indexOf('                  actions: [');
    final e = pagina.indexOf(']) glasInBalk(actie, plat: isCompact(context)),', a);
    expect(a, greaterThan(-1));
    expect(e, greaterThan(a));
    return pagina.substring(a, e);
  }

  test('in de balk: alleen het boekje en ⋯', () {
    final b = balk();
    expect(b, contains("tooltip: 'Boekje doorbladeren',"));
    expect(b, contains("tooltip: 'Meer',"));
    for (final weg in [
      'Uitgave kiezen — met hoes, achterkant en cd',
      'Tags gelijktrekken — één album',
      'Herkennen op geluid',
      'Een ander album hierin samenvoegen',
      'Metadata corrigeren',
      'Album verwijderen',
    ]) {
      expect(b, isNot(contains(weg)), reason: '"$weg" hoort in het menu, niet als knop over de hoes');
    }
  });

  test('het menu heeft elke actie die er stond', () {
    final a = pagina.indexOf('ItemMenu _albumKopMenu()');
    expect(a, greaterThan(-1));
    final menu = pagina.substring(a, pagina.indexOf('\n  }\n', a));
    for (final regel in [
      "'Uitgave kiezen…'",
      "'Tags gelijktrekken'",
      "'Herkennen op geluid'",
      "'Tags terugzetten'",
      "'Ander album hierin samenvoegen…'",
      "'Metadata corrigeren…'",
      "'Album verwijderen…'",
    ]) {
      expect(menu, contains(regel));
    }
    // Dezelfde voorwaarden als de knoppen: bestanden aanpassen alleen waar de bibliotheek hier woont.
    expect(menu, contains('if (!album.isSingle && lokaal)'));
    expect(menu, contains('if (!album.isSingle && lokaal && lib.undoableTagWrites(album) > 0)'));
  });
}
