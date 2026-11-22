/// De tegel van een verzameling is een poster en geen hoes (Saber, 22-11-2026: *"verzameling cover moet wel duidelijker,
/// nu denk ik dat dit 1 album is, het moet de genre voorstellen"* — gekozen: "C · genreposter").
library;

import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/main.dart' show VerzamelingPoster, posterKleur, verzamelingIcoon;
import 'package:debridmusic/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('DE KERN: een icoon voor het genre, uit de naam', () {
    expect(verzamelingIcoon('Vocal jazz'), Icons.mic_rounded);
    expect(verzamelingIcoon('Crooners & standards'), Icons.mic_rounded);
    expect(verzamelingIcoon('Klassiek & opera'), Icons.piano_rounded);
    expect(verzamelingIcoon('Kindermuziek'), Icons.child_care_rounded);
    expect(verzamelingIcoon('Soul classics'), Icons.graphic_eq_rounded);
    expect(verzamelingIcoon('Raï & Arabische pop'), Icons.public_rounded);
    expect(verzamelingIcoon('Hardcore & gabber'), Icons.bolt_rounded);
    expect(verzamelingIcoon('Franse chanson'), Icons.local_florist_rounded);
    expect(verzamelingIcoon('Reggae'), Icons.wb_sunny_rounded);
    expect(verzamelingIcoon('Voor de zondag'), Icons.collections_bookmark_rounded, reason: 'niets herkend');
  });

  test('DE KERN: de kleur van de hoezen, donker genoeg voor witte letters en niet grauw', () {
    final rood = HSLColor.fromColor(posterKleur('Soul classics', 0xFFE24B4A));
    expect(rood.lightness, closeTo(.3, .01));
    expect(rood.hue, closeTo(HSLColor.fromColor(const Color(0xFFE24B4A)).hue, 1));
    final grauw = HSLColor.fromColor(posterKleur('x', 0xFF8A8580));
    expect(grauw.saturation, greaterThanOrEqualTo(.34), reason: 'een bijna grijze hoes geeft geen grijze poster');
  });

  test('zonder kleur: elke keer dezelfde tint voor dezelfde naam, en een andere voor een andere', () {
    expect(posterKleur('Vocal jazz', null), posterKleur('Vocal jazz', null));
    expect(posterKleur('vocal JAZZ', null), posterKleur('Vocal jazz', null));
    expect(posterKleur('Raï & Arabische pop', null), isNot(posterKleur('Vocal jazz', null)));
    expect(HSLColor.fromColor(posterKleur('Vocal jazz', null)).lightness, closeTo(.3, .01));
  });

  testWidgets('de poster: de naam groot, het icoon, en hoogstens drie kleine hoezen', (tester) async {
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
    Album plaat(String titel, {bool hoes = true}) =>
        Album(titel, 'X', [Track(path: 'p/$titel.flac', title: titel, artist: 'X', album: titel)])
          ..embeddedCover = hoes ? png : null;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VerzamelingPoster(
            naam: 'Vocal jazz', albums: [for (final t in ['a', 'b', 'c', 'd']) plaat(t), plaat('e', hoes: false)], maat: 200),
      ),
    ));
    expect(find.text('Vocal jazz'), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(3), reason: 'vier platen met een hoes, maar hoogstens drie op de poster');
    expect(find.byKey(const ValueKey('verzameling-poster-Vocal jazz')), findsOneWidget);
  });

  test('aangesloten: de tegel van een verzameling is de poster, geen hoes van één plaat', () {
    final m = _bron('lib/main.dart');
    expect(m, contains('    hoes: (maat) => VerzamelingPoster(naam: naam, albums: albums, maat: maat),'));
    expect(m, contains('    ].take(3).toList();'));
  });
}
