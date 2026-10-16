/// Glas op een iPad en een gsm: echte vervaging, maar GEDEELD — en plat zodra het te veel kost.
///
/// **Waarom het eerst plat was.** De warmtemeter van 3.9.458 mat op 10-10-2026 op de iPad (120 Hz,
/// 1668×2388 px) per beeld 1,4 ms rasteren op schermen met 0–2 glasvlakken, en gemiddeld 6,5 ms (tot
/// 24 ms) met 8 of meer — de albumpagina en Nu speelt, waar de cd 60 keer per seconde om een beeld
/// vraagt. Elke `BackdropFilter` las het scherm apart terug; de GPU stond tot 100 %.
///
/// **Waarom het nu weer mag (16-10-2026).** Saber koos vloeibaar glas, overal. Alle matte vlakken
/// hebben nu één filter ([glasMat]) onder één `BackdropGroup`: één terugleesbeurt voor allemaal. En
/// de bewaker in `ui/glas.dart` zet het glas plat als de tekentijd te hoog wordt — dan geldt de oude
/// regel weer: geen enkel glas leest het scherm terug.
library;

import 'dart:io';

import 'package:debridmusic/main.dart' show glassSurface;
import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/glas.dart';
import 'package:debridmusic/ui/vlak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een iPad liggend: 1194 punten breed, dus níét compact.
Future<List<BackdropFilter>> _lagen(WidgetTester t, Widget kind, {double breed = 1194}) async {
  await t.pumpWidget(MediaQuery(
    data: MediaQueryData(size: Size(breed, 834)),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(home: Scaffold(body: Center(child: kind))),
    ),
  ));
  await t.pump();
  return t.widgetList<BackdropFilter>(find.byType(BackdropFilter)).toList();
}

Widget get _knop => GlasKnop(icoon: Icons.radio_rounded, label: 'Radio', onPressed: () {});
Widget get _pil => glassSurface(child: const SizedBox(width: 200, height: 40));
Widget get _balk => SizedBox(width: 600, height: 60, child: balkGlas(const Color(0xFF07080C), 1));

void main() {
  setUp(() {
    bureaubladVoorToets = false;
    GlasKwaliteit.vergeet();
  });
  tearDown(() {
    bureaubladVoorToets = null;
    setTvModeForTest(false);
    GlasKwaliteit.vergeet();
  });

  group('matglas op een iPad: echt, en allemaal met hetzelfde filter', () {
    testWidgets('knop, pil en balk vervagen, en alle drie met glasMat', (t) async {
      for (final w in [_knop, _pil, _balk]) {
        final l = await _lagen(t, w);
        expect(l, hasLength(1));
        expect(identical(l.single.filter, glasMat), isTrue,
            reason: 'alleen GELIJKE filters worden in een BackdropGroup samen teruggelezen');
      }
    });
  });

  group('DE KERN van 10-10-2026 blijft: plat glas leest niets terug', () {
    testWidgets('als de bewaker het glas plat zet', (t) async {
      GlasKwaliteit.stand.value = GlasStand.plat;
      expect(await _lagen(t, _knop), isEmpty);
      expect(await _lagen(t, _pil), isEmpty);
      expect(await _lagen(t, _balk), isEmpty);
    });

    testWidgets('en op een televisie altijd', (t) async {
      setTvModeForTest(true);
      await GlasKwaliteit.inrichten();
      expect(GlasKwaliteit.stand.value, GlasStand.plat);
      expect(glasZonderVervaging, isTrue);
    });
  });

  test('de balk boven de albumpagina krijgt zonder vervaging de dichte vulling', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('final dicht = isCompact(context) || glasZonderVervaging;'), isTrue);
  });

  test('de regel: plat op een tv of als de bewaker het zegt, niet meer per soort toestel', () {
    GlasKwaliteit.stand.value = GlasStand.mat;
    bureaubladVoorToets = false;
    expect(glasZonderVervaging, isFalse, reason: 'een iPad, een telefoon: nu wel glas');
    bureaubladVoorToets = true;
    expect(glasZonderVervaging, isFalse, reason: 'Windows, Mac, Linux');
    GlasKwaliteit.stand.value = GlasStand.plat;
    expect(glasZonderVervaging, isTrue);
  });

  test('één groep bovenaan de app, boven de Navigator', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main, contains('inhoud = BackdropGroup(child: inhoud);'));
    expect(main, contains('unawaited(GlasKwaliteit.inrichten());'));
  });
}
