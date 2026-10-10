/// Op een iPad vervaagt het glas niets meer — net als op de telefoon en de televisie.
///
/// **Waarom.** De warmtemeter van 3.9.458 mat op 10-10-2026 op de iPad (120 Hz, 1668×2388 px) per
/// beeld 1,4 ms rasteren op schermen met 0–2 glasvlakken, en gemiddeld 6,5 ms (tot 24 ms) met 8 of
/// meer — de albumpagina en Nu speelt, waar de cd 60 keer per seconde om een beeld vraagt. Een
/// `BackdropFilter` leest bij elk beeld het scherm terug en vervaagt het opnieuw; de GPU stond tot
/// 100 % en de batterij zakte 10 % in elf minuten. Het glas hing aan de BREEDTE (`isCompact`), en een
/// iPad is breed. Nu hangt het aan het soort toestel: vervagen alleen op een bureaublad.
library;

import 'dart:io';

import 'package:debridmusic/main.dart' show glassSurface;
import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/vlak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een iPad liggend: 1194 punten breed, dus níét compact.
Future<int> _lagen(WidgetTester t, Widget kind, {double breed = 1194}) async {
  await t.pumpWidget(MediaQuery(
    data: MediaQueryData(size: Size(breed, 834)),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(home: Scaffold(body: Center(child: kind))),
    ),
  ));
  await t.pump();
  return t.widgetList(find.byType(BackdropFilter)).length;
}

Widget get _knop => GlasKnop(icoon: Icons.radio_rounded, label: 'Radio', onPressed: () {});
Widget get _pil => glassSurface(child: const SizedBox(width: 200, height: 40));
Widget get _balk => SizedBox(width: 600, height: 60, child: balkGlas(const Color(0xFF07080C), 1));

void main() {
  tearDown(() => bureaubladVoorToets = null);

  group('DE KERN: op een iPad leest geen enkel glas het scherm terug', () {
    setUp(() => bureaubladVoorToets = false);

    testWidgets('de glazen knop (tien tot veertien op de albumpagina)', (t) async {
      expect(await _lagen(t, _knop), 0);
    });

    testWidgets('de pil bovenaan', (t) async {
      expect(await _lagen(t, _pil), 0);
    });

    testWidgets('de meeschuivende balk', (t) async {
      expect(await _lagen(t, _balk), 0);
    });

  });

  test('de balk boven de albumpagina krijgt zonder vervaging de dichte vulling', () {
    // Zonder vervaging draagt alleen de kleur nog de leesbaarheid; met 62 % las je op de telefoon
    // de albumbeschrijving dwars door de knoppen heen. Dus dezelfde 78 % als daar.
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('final dicht = isCompact(context) || glasZonderVervaging;'), isTrue);
  });

  group('DE GRENS: op een bureaublad blijft het echt glas', () {
    setUp(() => bureaubladVoorToets = true);

    testWidgets('knop, pil en balk vervagen daar wel', (t) async {
      expect(await _lagen(t, _knop), 1);
      expect(await _lagen(t, _pil), 1);
      expect(await _lagen(t, _balk), 1);
    });
  });

  test('zonder vastzetten kijkt de regel naar het echte platform', () {
    // Deze toetsen draaien op een bureaublad (Windows hier, Linux op de bouwstraat): daar hoort het
    // glas aan te blijven. Zonder deze toets kon "bureaublad" stil op onwaar vallen en verdween het
    // glas ook van de pc.
    bureaubladVoorToets = null;
    expect(isBureaublad, isTrue);
    expect(glasZonderVervaging, isFalse);
  });

  test('de regel zelf', () {
    bureaubladVoorToets = false;
    expect(glasZonderVervaging, isTrue, reason: 'een iPad, een telefoon');
    bureaubladVoorToets = true;
    expect(glasZonderVervaging, isFalse, reason: 'Windows, Mac, Linux');
  });
}
