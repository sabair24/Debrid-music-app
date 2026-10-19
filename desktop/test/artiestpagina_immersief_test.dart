/// De artiestpagina op een gsm (Saber, 19-10-2026): "bij het scrollen ter hoogte van de foto voelt het
/// niet vlot" en "op de gsm moet de foto doorlopen tot boven het scherm, full immersive".
///
/// Gemeten op de S26 vóór deze wijziging: tekenen 10,4–10,9 ms per beeld bij schuiven over de foto en
/// 8,6–9,3 ms met de kop uit beeld (budget 8,3 ms bij 120 Hz; andere pagina's 3–6 ms). De vaste kost
/// was de vervaagde achtergrond: een `ImageFiltered` van σ60 over het hele scherm, elk beeld opnieuw.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/ui/vlak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

/// Een effen foto als png-bytes, zonder netwerk.
Future<Uint8List> _foto() async {
  final r = ui.PictureRecorder();
  Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 40, 60), Paint()..color = const Color(0xFFB04020));
  final beeld = await r.endRecording().toImage(40, 60);
  final b = await beeld.toByteData(format: ui.ImageByteFormat.png);
  beeld.dispose();
  return b!.buffer.asUint8List();
}

/// Laat het decoderen en het bakken (allebei echt asynchroon) hun werk doen.
Future<void> _laatBakken(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump();
  }
}

Widget _omhulsel(Widget kind) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
        ChangeNotifierProvider<AppSettings>(create: (_) => AppSettings()),
      ],
      child: MaterialApp(home: Scaffold(body: ListView(children: [kind]))),
    );

void main() {
  setUpAll(() {
    setAppDirForTest(Directory.systemTemp.createTempSync('artiestimmersief').path);
  });

  group('de vervaagde achtergrond', () {
    testWidgets('DE KERN: één keer gebakken, daarna een gewone afbeelding en geen vervaging per beeld', (t) async {
      final bytes = (await t.runAsync(_foto))!;
      Widget pagina(double hoogte) => Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: SizedBox(width: 300, height: hoogte, child: GebakkenWaas(beeld: bytes))),
          );
      await t.pumpWidget(pagina(600));
      await _laatBakken(t);
      final beeld = find.byKey(const ValueKey('gebakken-waas'));
      expect(beeld, findsOneWidget);
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      final eerste = t.widget<RawImage>(beeld).image;
      expect(eerste, isNotNull);

      // Opnieuw bouwen met dezelfde foto en maat: niets opnieuw gebakken.
      await t.pumpWidget(pagina(600));
      await _laatBakken(t);
      expect(identical(t.widget<RawImage>(beeld).image, eerste), isTrue);

      // Een andere maat (draaien, venster slepen): wel opnieuw.
      await t.pumpWidget(pagina(500));
      await _laatBakken(t);
      expect(identical(t.widget<RawImage>(beeld).image, eerste), isFalse);
    });

    testWidgets('één bakbeurt, ook als er beelden voorbijgaan terwijl hij nog loopt', (t) async {
      final bytes = (await t.runAsync(_foto))!;
      GebakkenWaas.bakBeurten = 0;
      Widget pagina() => Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: SizedBox(width: 300, height: 600, child: GebakkenWaas(beeld: bytes))),
          );
      await t.pumpWidget(pagina());
      // Alleen het decoderen laten lopen, tot de eerste bakbeurt start.
      for (var i = 0; i < 10 && GebakkenWaas.bakBeurten == 0; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump();
      }
      expect(GebakkenWaas.bakBeurten, 1);
      // Opnieuw gebouwd terwijl het bakken loopt (de pagina erboven verandert): geen tweede beurt.
      for (var i = 0; i < 5; i++) {
        await t.pumpWidget(pagina());
      }
      expect(GebakkenWaas.bakBeurten, 1);
      await _laatBakken(t);
      expect(GebakkenWaas.bakBeurten, 1);
      expect(find.byKey(const ValueKey('gebakken-waas')), findsOneWidget);
    });

    test('aangesloten: ArtistBackdrop bakt en vervaagt niet meer elk beeld', () {
      final main = _bron('lib/main.dart');
      final begin = main.indexOf('class _ArtistBackdropState');
      final eind = main.indexOf('\nclass ', begin + 10);
      final klasse = main.substring(begin, eind);
      expect(klasse, contains('if (img != null) GebakkenWaas(beeld: img),'));
      expect(klasse, isNot(contains('ImageFiltered(')));
    });
  });

  group('de foto tot bovenaan het scherm van een gsm', () {
    /// Het verloop achter de statusbalk, herkend aan waar hij op uitkomt (27 procent, donker thema).
    LinearGradient rand(WidgetTester t) {
      final f = find.byWidgetPredicate((w) {
        if (w is! DecoratedBox) return false;
        final d = w.decoration;
        if (d is! BoxDecoration || d.gradient is! LinearGradient) return false;
        final g = d.gradient! as LinearGradient;
        return g.begin == Alignment.topCenter && g.colors.last == const Color(0x44000000) && g.colors.first != g.colors.last;
      });
      expect(f, findsOneWidget);
      return (t.widget<DecoratedBox>(f).decoration as BoxDecoration).gradient! as LinearGradient;
    }

    EditorialeKop kop({required bool zacht}) => EditorialeKop(
          naam: 'Alabina',
          soort: 'Group · France',
          bibliotheek: '1 album · 18 nummers',
          bovenBloed: 40,
          bloedZacht: zacht,
          actions: [FilledButton(onPressed: () {}, child: const Text('Radio'))],
        );

    testWidgets('achter de statusbalk een zachte rand (55 %), achter de balk van de pc de dichte (85 %)', (t) async {
      await t.pumpWidget(_omhulsel(kop(zacht: true)));
      expect((rand(t).colors.first.a * 255).round(), 0x8C);
      await t.pumpWidget(_omhulsel(kop(zacht: false)));
      expect((rand(t).colors.first.a * 255).round(), 0xD9);
    });

    test('aangesloten: op een gsm geen SafeArea bovenaan, en de kop, de rand en de terugknop kennen de statusbalk', () {
      final main = _bron('lib/main.dart');
      expect(main, contains(
          'final bloed = ruimte > 0 ? ruimte : (isCompact(context) && !isTv ? MediaQuery.paddingOf(context).top : 0.0);'));
      expect(main, contains('        top: bloed == 0,\n        child: CustomScrollView(\n        controller: _rol,'));
      expect(main, contains('                  bovenBloed: bloed,\n'));
      expect(main, contains('                  bloedZacht: ruimte == 0,\n'));
      expect(main, contains('padding: EdgeInsets.fromLTRB(10 + tvOverscan.left, 8 + bloed, 0, 0),'));
    });
  });
}
