// De minispeler en de onderbalk als glas óver de pagina's (Saber, 16-10-2026: "Minispeler en onderbalk"
// van glas, de inhoud schuift eronder door). De pagina's krijgen de hoogte van de balken als extra
// ondermarge, boven de navigator, en elke lijst met een eigen marge telt die mee (onderOp).
import 'dart:io';

import 'package:debridmusic/main.dart' show kGlasBalkenHoogte, metGlasBalken, onderOp, balkOpGlas;
import 'package:debridmusic/ui/glas.dart';
import 'package:debridmusic/ui/vlak.dart' show balkKleur;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(GlasKwaliteit.vergeet);

  test('de balken samen: minispeler 52 en onderbalk 48', () {
    expect(kGlasBalkenHoogte, 100);
  });

  testWidgets('de pagina krijgt de balken als ondermarge, bovenop de systeembalk', (t) async {
    await t.binding.setSurfaceSize(const Size(384, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    double? onder;
    late EdgeInsets lijst;
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(384, 800), padding: EdgeInsets.only(bottom: 24)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) => metGlasBalken(
            context,
            glas: true,
            balken: const SizedBox(height: 124, child: Placeholder()),
            pagina: Builder(builder: (context) {
              onder = MediaQuery.paddingOf(context).bottom;
              lijst = onderOp(context, const EdgeInsets.only(bottom: 32));
              return const SizedBox.expand();
            }),
          ),
        ),
      ),
    ));
    expect(onder, 24 + kGlasBalkenHoogte);
    expect(lijst.bottom, 32 + 24 + kGlasBalkenHoogte, reason: 'een lijst met een eigen marge telt hem mee');
    // De balken liggen onderaan, óver de pagina.
    expect(t.getRect(find.byType(Placeholder)).bottom, 800);
  });

  testWidgets('zonder glas (tv, toetsenbord, breed scherm) verandert er niets', (t) async {
    double? onder;
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(384, 800), padding: EdgeInsets.only(bottom: 24)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) => metGlasBalken(
            context,
            glas: false,
            balken: const Placeholder(),
            pagina: Builder(builder: (context) {
              onder = MediaQuery.paddingOf(context).bottom;
              return const SizedBox.expand();
            }),
          ),
        ),
      ),
    ));
    expect(onder, 24);
    expect(find.byType(Placeholder), findsNothing);
  });

  test('op glas doorschijnend, plat glas dicht', () {
    GlasKwaliteit.stand.value = GlasStand.mat;
    expect(balkOpGlas(0xFFCC2222).a, closeTo(kGlasDekking, .01));
    expect(kGlasDekking, greaterThanOrEqualTo(.8), reason: 'Saber, 16-10-2026: "alles is veel te transparant" (bij 58 %)');
    GlasKwaliteit.stand.value = GlasStand.plat;
    expect(balkOpGlas(0xFFCC2222), balkKleur(0xFFCC2222));
  });

  test('aangesloten: alleen op een gsm staand, en elke lijst onder de schil telt mee', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main, contains('final glasBalken = isCompact(context) && !isTv && MediaQuery.viewInsetsOf(context).bottom == 0;'));
    expect(main, contains('child: metGlasBalken(\n                context,\n                glas: glasBalken,'));
    expect(main, contains('if (MediaQuery.viewInsetsOf(context).bottom == 0 && !glasBalken) ...['));
    expect(main, contains('PlayerBar(metSysteeminzet: false, opGlas: true)'));
    // Twintig lijsten en pagina's onder de schil (geteld op 16-10-2026): zestien met onderOp, drie
    // met een laatste SizedBox, en de afspeellijst die zijn marge zelf uitrekent.
    expect('onderOp(context,'.allMatches(main).length, greaterThanOrEqualTo(16));
    expect('SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom)'.allMatches(main).length, 3);
    expect(main, contains('20, 12 + MediaQuery.paddingOf(context).bottom),'));
    // Het radioblad opent over de balken heen.
    final r = main.indexOf('Future<void> toonRadioUitZin(BuildContext context) async {');
    expect(main.substring(r, r + 400), contains('useRootNavigator: true,'));
  });
}
