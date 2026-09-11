/// De hoes als beeld bovenaan een albumpagina — en nergens een rand waar hij ophoudt.
///
/// **Waarom dit er is.** Na de artiestpagina, waar de foto tot de bovenrand van het venster loopt,
/// vroeg Saber op 11-09-2026 hetzelfde voor de albumpagina, en koos van drie voorstellen de vervaagde
/// hoes. Zo'n beeld heeft drie manieren om er slordig uit te zien die je in een toets die alleen
/// telt of er iets STAAT niet ziet: het houdt onderaan hard op in plaats van op te lossen, het blijft
/// staan terwijl de kop onder het venster uit schuift, of het tekent een donkere rand achter een balk
/// die er niet is. Elk van die drie staat hier.
library;

import 'dart:typed_data';

import 'package:debridmusic/ui/vlak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget pagina({ImageProvider? beeld, double balk = 0, ScrollController? rol}) => MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: HoesAchtergrond(beeld: beeld, hoogte: 400, balkRuimte: balk, rol: rol),
              ),
              if (rol != null)
                ListView(controller: rol, children: const [SizedBox(height: 3000)]),
            ],
          ),
        ),
      );

  final hoes = MemoryImage(_png);

  /// De rand achter de balk: het verloop dat met 85 procent zwart begint.
  final rand = find.byWidgetPredicate((w) {
    if (w is! DecoratedBox) return false;
    final d = w.decoration;
    return d is BoxDecoration &&
        d.gradient is LinearGradient &&
        (d.gradient! as LinearGradient).colors.first == const Color(0xD9000000);
  });

  testWidgets('DE VAL: zonder hoes tekent hij niets', (t) async {
    // Een plaat zonder hoes houdt zijn kleurwas, of gewoon de achtergrond — geen grijs vlak.
    await t.pumpWidget(pagina());
    expect(find.byType(ImageFiltered), findsNothing);
    expect(rand, findsNothing);
  });

  testWidgets('DE KERN: vervaagd, en onderaan lost hij op in plaats van te stoppen', (t) async {
    await t.pumpWidget(pagina(beeld: hoes));
    expect(t.widget<ImageFiltered>(find.byType(ImageFiltered)).imageFilter,
        HoesAchtergrond.vervaging,
        reason: 'scherp opgerekt wordt een hoes van 1200 pixels korrelig op een breed scherm');

    // Het masker ligt op het BEELD, niet een zwart verloop eroverheen: dat laatste maakt het beeld
    // donker in plaats van het te laten verdwijnen, en dan staat er waar het ophoudt alsnog een rand.
    final masker = t.widget<ShaderMask>(find.byType(ShaderMask));
    expect(masker.blendMode, BlendMode.dstIn);
    expect(HoesAchtergrond.vervloeiing.colors.last.a, 0,
        reason: 'onderaan hoort er niets meer van over te zijn, anders loopt er een streep');
    expect(find.descendant(of: find.byType(ShaderMask), matching: find.byType(ColoredBox)),
        findsOneWidget,
        reason: 'de donkering moet mee oplossen; blijft ze staan, dan houdt ze onderaan hard op');
  });

  testWidgets('DE KERN: hij schuift mee met de pagina, en nooit omlaag', (t) async {
    final rol = ScrollController();
    addTearDown(rol.dispose);
    await t.pumpWidget(pagina(beeld: hoes, rol: rol));

    double schuif() => t
        .widget<Transform>(find
            .descendant(of: find.byType(HoesAchtergrond), matching: find.byType(Transform))
            .first)
        .transform
        .getTranslation()
        .y;

    rol.jumpTo(120);
    await t.pump();
    expect(schuif(), -120, reason: 'de kop schuift weg en het beeld blijft achter in het venster');

    rol.jumpTo(0);
    await t.pump();
    expect(schuif(), 0);
  });

  testWidgets('DE GRENS: de rand achter de balk alleen als er een balk overheen zweeft', (t) async {
    // Op een telefoon en een televisie zweeft er niets; daar zou een donkere rand bovenaan alleen
    // een donkere rand zijn.
    await t.pumpWidget(pagina(beeld: hoes));
    expect(rand, findsNothing);

    await t.pumpWidget(pagina(beeld: hoes, balk: 64));
    expect(rand, findsOneWidget);
    expect(t.getSize(rand).height, 64);
    final g = (t.widget<DecoratedBox>(rand).decoration as BoxDecoration).gradient! as LinearGradient;
    expect(g.colors.last.a, 0,
        reason: 'de hoes heeft zijn eigen donkering; eindigt de rand niet doorzichtig, dan telt die '
            'donkering in de balk dubbel en staat er op de onderrand van de balk een streep');
  });
}

/// Een geldige 1×1 PNG: klein genoeg om in een toets te staan, echt genoeg om te decoderen.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
