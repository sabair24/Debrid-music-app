/// De stilstaande kleurvlekken uit de hoes, achter het glas van de balk (Saber, 18-10-2026).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/artwork.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Een hoes van 96 bij 96 met [kleur] per pixel.
Uint8List _hoes(img.Color Function(int x, int y) kleur) {
  final im = img.Image(width: 96, height: 96);
  for (var y = 0; y < 96; y++) {
    for (var x = 0; x < 96; x++) {
      im.setPixel(x, y, kleur(x, y));
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  test('links rood en rechts blauw: twee vlekken, elk op zijn plek', () {
    final v = hoesVlekken(_hoes((x, y) => x < 48 ? img.ColorRgb8(210, 30, 40) : img.ColorRgb8(30, 60, 200)));
    expect(v, hasLength(2));
    final rood = v.firstWhere((e) => (e.kleur >> 16 & 0xFF) > 150);
    final blauw = v.firstWhere((e) => (e.kleur & 0xFF) > 150);
    expect(rood.x, closeTo(.25, .05));
    expect(blauw.x, closeTo(.75, .05));
    expect(rood.y, closeTo(.5, .05));
    expect(v.first.gewicht, 1.0, reason: 'de zwaarste weegt 1');
  });

  test('een grijze of zwart-witte hoes heeft geen vlekken', () {
    expect(hoesVlekken(_hoes((x, y) => img.ColorRgb8(128, 128, 128))), isEmpty);
    expect(hoesVlekken(_hoes((x, y) => (x + y).isEven ? img.ColorRgb8(0, 0, 0) : img.ColorRgb8(255, 255, 255))), isEmpty);
  });

  test('tinten die op elkaar lijken worden één vlek, en hoogstens vier', () {
    final v = hoesVlekken(_hoes((x, y) => img.ColorRgb8(200 + (x % 8), 40 + (y % 8), 40)));
    expect(v, hasLength(1), reason: 'vier tinten van hetzelfde rood zijn één kleur');
    final bont = hoesVlekken(_hoes((x, y) => switch ((x ~/ 24 + y ~/ 48 * 4) % 6) {
          0 => img.ColorRgb8(220, 30, 30),
          1 => img.ColorRgb8(30, 200, 40),
          2 => img.ColorRgb8(30, 40, 220),
          3 => img.ColorRgb8(230, 200, 20),
          4 => img.ColorRgb8(200, 30, 200),
          _ => img.ColorRgb8(20, 200, 200),
        }));
    expect(bont.length, 4);
  });

  test('een onleesbare hoes geeft niets, en geen fout', () {
    expect(hoesVlekken(Uint8List.fromList([1, 2, 3])), isEmpty);
  });

  test('aangesloten: de speler rekent ze uit met de kleur, beide balken tekenen ze', () {
    final speler = File('lib/player.dart').readAsStringSync();
    expect(speler, contains('uit = await kleurEnVlekkenBuitenDeTekendraad(bytes);'));
    expect(speler, contains('    hoesVlekken = const [];'), reason: 'een nieuwe plaat begint zonder de vlekken van de vorige');
    final main = File('lib/main.dart').readAsStringSync();
    expect('HoesVlekkenSchilder(p.hoesVlekken'.allMatches(main).length, 2, reason: 'de brede en de smalle balk');
  });
}
