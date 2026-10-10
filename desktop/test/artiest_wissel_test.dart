/// Het artiestlogo boven de hoes springt niet meer bij een nummerwissel.
///
/// **Waarom.** Saber op 10-10-2026, na de reparatie van de hoezen: *"is dit ook zo voor de naam van
/// de artist via the audio DB ?"* Ja. `CoverEnricher.artistArt` las bij elke vraag het JSON-bestand
/// en vijf beelden opnieuw van schijf, dus een nieuw bytes-object, dus voor Flutter een nieuw beeld.
/// En `ArtiestKop` toonde bij een andere artiest eerst de naam als TEKST en een tel later het logo —
/// een andere hoogte, zodat de hoes eronder meesprong.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/cachesleutel.dart';
import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

/// Een echt PNG-logo, groot genoeg dat de verrijking het als bewaard beeld aanneemt (> 100 bytes).
Uint8List _logoPng() {
  final b = img.Image(width: 40, height: 16);
  for (var x = 0; x < 40; x++) {
    for (var y = 0; y < 16; y++) {
      b.setPixelRgba(x, y, (x * 6) % 256, (y * 15) % 256, (x * y) % 256, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(b));
}

CoverEnricher get _verrijker => CoverEnricher(AppSettings());

/// Een artiest met een bewaard logo op schijf, zoals de verrijking hem achterlaat.
void _artiest(String naam) {
  final dir = Directory('$appDir${Platform.pathSeparator}artistart')..createSync(recursive: true);
  final k = fnv1a(naam.toLowerCase());
  File('${dir.path}${Platform.pathSeparator}$k.json')
      .writeAsStringSync(jsonEncode({'v': 3, 'logo': 'https://voorbeeld.invalid/$k.png'}));
  final logo = _logoPng();
  expect(logo.length, greaterThan(100));
  File('${dir.path}${Platform.pathSeparator}${k}_logo.img').writeAsBytesSync(logo);
}

Widget _omhulsel(Widget kind) => ChangeNotifierProvider<AppSettings>(
      create: (_) => AppSettings(),
      child: MaterialApp(home: Scaffold(body: Center(child: kind))),
    );

Uint8List? _logoOpHetScherm(WidgetTester t) {
  for (final i in t.widgetList<Image>(find.byType(Image))) {
    if (i.image case ResizeImage(imageProvider: MemoryImage(:final bytes))) return bytes;
  }
  return null;
}

void main() {
  setUpAll(() => setAppDirForTest(Directory.systemTemp.createTempSync('dm_artiestwissel_').path));
  setUp(CoverEnricher.vergeetArtiestGelezenVoorToets);

  group('het geheugen van de artiestbeelden', () {
    test('DE KERN: twee keer vragen geeft HETZELFDE object en dezelfde logobytes', () async {
      _artiest('Bazart');
      final een = await _verrijker.artistArt('Bazart');
      final twee = await _verrijker.artistArt('Bazart');
      expect(een?.logoBytes, isNotNull);
      expect(identical(een, twee), isTrue);
      expect(identical(een!.logoBytes, twee!.logoBytes), isTrue,
          reason: 'anders decodeert Flutter het logo bij elke vraag opnieuw');
    });

    test('meteen beschikbaar zodra hij eens gelezen is, ongeacht hoofdletters', () async {
      _artiest('Clouseau');
      expect(_verrijker.artistArtInGeheugen('Clouseau'), isNull);
      final gelezen = await _verrijker.artistArt('Clouseau');
      expect(identical(_verrijker.artistArtInGeheugen('CLOUSEAU'), gelezen), isTrue);
    });

    test('hoogstens tweeëndertig artiesten', () async {
      for (var i = 0; i <= CoverEnricher.kArtiestGelezenMax; i++) {
        _artiest('Artiest $i');
        await _verrijker.artistArt('Artiest $i');
      }
      expect(_verrijker.artistArtInGeheugen('Artiest 0'), isNull);
      expect(_verrijker.artistArtInGeheugen('Artiest ${CoverEnricher.kArtiestGelezenMax}'), isNotNull);
    });
  });

  group('DE KERN: ArtiestKop bij een wissel', () {
    testWidgets('ligt de volgende artiest in het geheugen, dan staat zijn logo er meteen — geen tekst eerst',
        (tester) async {
      _artiest('Niels Destadsbader');
      _artiest('Bart Peeters');
      final volgende = (await tester.runAsync(() => _verrijker.artistArt('Bart Peeters')))!;

      await tester.pumpWidget(_omhulsel(const ArtiestKop(naam: 'Niels Destadsbader')));
      await tester.pumpWidget(_omhulsel(const ArtiestKop(naam: 'Bart Peeters')));
      expect(find.text('Bart Peeters'), findsNothing, reason: 'eerst de naam als tekst is de sprong');
      expect(identical(_logoOpHetScherm(tester), volgende.logoBytes), isTrue);
    });

    testWidgets('het logo houdt het vorige beeld vast tot het volgende klaar is', (tester) async {
      _artiest('Pauline');
      await tester.runAsync(() => _verrijker.artistArt('Pauline'));
      await tester.pumpWidget(_omhulsel(const ArtiestKop(naam: 'Pauline')));
      final logo = tester.widget<Image>(find.byType(Image));
      expect(logo.gaplessPlayback, isTrue);
    });

    testWidgets('de artiest van het volgende nummer wordt alvast klaargezet', (tester) async {
      _artiest('Lara Fabian');
      _artiest('Céline Dion');
      expect(_verrijker.artistArtInGeheugen('Céline Dion'), isNull);
      await tester.pumpWidget(_omhulsel(const ArtiestKop(naam: 'Lara Fabian', volgende: 'Céline Dion')));
      // Het lezen begon binnen de nepklok van de toets: elke stap ervan wil echte tijd én een pump.
      for (var i = 0; i < 20 && _verrijker.artistArtInGeheugen('Céline Dion') == null; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(_verrijker.artistArtInGeheugen('Céline Dion'), isNotNull);
    });
  });

  test('Nu speelt geeft de artiest van het volgende nummer door, met dezelfde regel', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('volgende: volgendAlbum?.artist ?? volgendNummer?.artist,'), isTrue);
    expect(main.contains('final artiestVanPlaat = al?.artist ?? t?.artist ??'), isTrue,
        reason: 'dezelfde regel als voor het huidige nummer');
  });
}
