// Het lichte thema in de schermen (Saber, 18-10-2026): wat op donker wit of amber was omdat het daar
// opviel, moet op gebroken wit nog lezen — en op donker precies blijven wat het was.
import 'dart:io';

import 'package:debridmusic/ui/glas.dart' show kVlekLicht;
import 'package:debridmusic/ui/kleuren.dart';
import 'package:debridmusic/ui/maten.dart';
import 'package:debridmusic/ui/menu.dart';
import 'package:debridmusic/ui/vlak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// De kleuren die voor donker gekozen zijn en in de schermen staan (zie `leesbaar` in kleuren.dart).
const _voorDonker = [
  0xFFE8913A, 0xFFFF6B6B, 0xFFE0B341, 0xFFE0A33A, 0xFFFFB454, 0xFF8A90A6, 0xFFFF8A9B, 0xFFFFC9D1, 0xFFE0A44A,
  0xFF6C7387, 0xFF6BCB8B, 0xFF6BD49A, 0xFFF2C14E, 0xFFA9B6E8, 0xFF9DB4C8, 0xFF8FD3A6, 0xFFE89A6A, 0xFFE8C36A,
  0xFFB98A4A, 0xFFE07A7A, 0xFFF2A65A, 0xFF8A8F98, 0xFF8A8FA3, 0xFFC7CBDA, 0xFFFF5C8A, 0xFF00D48C, 0xFFFF4E63,
];

void main() {
  tearDown(() => Thema.licht = false);

  test('op donker verandert er niets', () {
    Thema.licht = false;
    for (final c in _voorDonker) {
      expect(leesbaar(Color(c)), Color(c));
    }
    expect(vlakOpThema(const Color(0xFF3A1E24)), const Color(0xFF3A1E24));
    expect(paginaWaas(0xDB), const Color(0xDB07080C));
    expect(paginaWaas(0x44, donker: Colors.black), const Color(0x44000000));
    expect(HoesAchtergrond.donkering, const Color(0xB307080C));
    expect(MenuTint.nu, same(MenuTint.paars));
    expect(MenuGlas.kleur, const Color(0xFF12121A));
    expect(kSchaduw2.last.color, const Color(0x73000000));
    expect(kFel, Colors.white);
  });

  test('op licht leest elke waarschuwings-, fout- en grijskleur 4,5:1, ook op het donkerste vlak', () {
    Thema.licht = true;
    for (final c in _voorDonker) {
      final l = leesbaar(Color(c));
      for (final vlak in [kAchtergrond, kVerzonken, kPaneel, kPaneelHoog, kBovenop]) {
        expect(contrast(l, vlak), greaterThanOrEqualTo(4.5), reason: '${c.toRadixString(16)} → $l op $vlak');
      }
      // Dezelfde soort kleur: amber blijft amber, geen grijs.
      final voor = HSLColor.fromColor(Color(c)), na = HSLColor.fromColor(l);
      if (voor.saturation > .3) expect((voor.hue - na.hue).abs(), lessThan(4), reason: 'tint van ${c.toRadixString(16)}');
    }
  });

  test('op licht: een donkerrode grond wordt lichtrood, een randje iets donkerder', () {
    Thema.licht = true;
    final vlak = vlakOpThema(const Color(0xFF3A1E24));
    final rand = vlakOpThema(const Color(0xFF5A4A1E), rand: true);
    expect(sterrenL(vlak), greaterThan(85));
    expect(sterrenL(rand), lessThan(sterrenL(vlakOpThema(const Color(0xFF2A2413)))));
    expect(contrast(leesbaar(const Color(0xFFFFC9D1)), vlak), greaterThanOrEqualTo(4.5),
        reason: 'de tekst van een foutmelding op zijn eigen grond');
  });

  test('op licht: wazen in gebroken wit, zachtere schaduwen, een witte menucapsule', () {
    Thema.licht = true;
    expect(paginaWaas(0xDB), kAchtergrond.withAlpha(0xDB));
    expect(HoesAchtergrond.donkering.a, closeTo(.70, .01));
    expect(HoesAchtergrond.donkering.withValues(alpha: 1), kAchtergrond);
    expect(kSchaduw2.last.color.a, lessThan(.2));
    expect(MenuTint.nu, same(MenuTint.paarsLicht));
    expect(contrast(MenuTint.nu.tekst, MenuGlas.kleur), greaterThanOrEqualTo(4.5), reason: 'paars woord op de witte capsule');
    expect(kFel, kTekst);
  });

  testWidgets('op licht: glasknoppen op een kop krijgen de dichtste onderlaag, en witte letters lezen', (t) async {
    Thema.licht = true;
    late double grond;
    await t.pumpWidget(Builder(builder: (context) {
      grond = KnopGrond.van(context);
      return const SizedBox();
    }));
    expect(grond, kGrondLichteKop);
    expect(glasOnderlaagVoor(grond), closeTo(.82, .001));
    expect(glasKnopContrast(grond), greaterThanOrEqualTo(4.5));
  });

  test('geen kleur voor donker meer zonder leesbaar ervoor', () {
    // Een nieuwe waarschuwing in #E8913A die niet door `leesbaar` gaat, is op licht onleesbaar.
    final fout = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll('\\', '/');
      if (!p.endsWith('.dart') || p.endsWith('ui/kleuren.dart') || p.endsWith('ui/stijl.dart')) continue;
      final regels = f.readAsLinesSync();
      for (var i = 0; i < regels.length; i++) {
        for (final c in _voorDonker) {
          final hex = 'Color(0x${c.toRadixString(16).toUpperCase()})';
          var at = regels[i].indexOf(hex);
          while (at >= 0) {
            final ervoor = regels[i].substring(0, at);
            if (!ervoor.endsWith('leesbaar(const ')) fout.add('$p:${i + 1}: $hex');
            at = regels[i].indexOf(hex, at + 1);
          }
        }
      }
    }
    expect(fout, isEmpty);
  });

  test('op de tv: gevulde knoppen (glas) krijgen in licht donkere letters', () {
    final bron = File('lib/main.dart').readAsStringSync();
    expect(bron, contains('filledButtonTheme: FilledButtonThemeData(style: _focusOutlineGevuld),'));
    expect(bron, contains('return Thema.licht ? kTekst : null;'));
  });

  test('op licht zijn de kleurvlekken van de hoes zachter; de cd-glans leest de schijf niet terug', () {
    expect(File('lib/ui/glas.dart').readAsStringSync(), contains('(Thema.licht ? sterkte * kVlekLicht : sterkte)'));
    expect(kVlekLicht, lessThan(.5));
    expect(File('lib/ui/getekende_schijf.dart').readAsStringSync(), isNot(contains('BlendMode.softLight')),
        reason: 'een menging die de draaiende schijf eronder terugleest, kost elk beeld een schermkopie');
  });

}
