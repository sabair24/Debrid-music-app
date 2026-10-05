/// De hoes als beeld bovenaan een albumpagina — en nergens een rand waar hij ophoudt.
///
/// **Waarom dit er is.** Na de artiestpagina, waar de foto tot de bovenrand van het venster loopt,
/// vroeg Saber op 11-09-2026 hetzelfde voor de albumpagina, en koos van drie voorstellen de vervaagde
/// hoes. Zo'n beeld heeft drie manieren om er slordig uit te zien die je in een toets die alleen
/// telt of er iets STAAT niet ziet: het houdt onderaan hard op in plaats van op te lossen, het blijft
/// staan terwijl de kop onder het venster uit schuift, of het tekent een donkere rand achter een balk
/// die er niet is. Elk van die drie staat hier.
///
/// **En sinds 05-10-2026 een vierde: het mag niet elk beeld opnieuw vervaagd worden.** Op Sabers S26
/// miste scrollen bovenaan een albumpagina 10–11 beelden per ronde, onderaan dezelfde pagina 1 tot
/// 3 — en het enige verschil was deze waas. Hij wordt nu één keer gebakken
/// ([bakHoesAchtergrond]); de toets hieronder legt vast dat het gebakken beeld hetzelfde is als wat
/// er per beeld getekend werd.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:debridmusic/ui/vlak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    expect(find.byType(RawImage), findsNothing);
    expect(rand, findsNothing);
  });

  testWidgets('DE KERN: één gebakken beeld, en per beeld geen vervaging en geen masker', (t) async {
    await t.pumpWidget(pagina(beeld: hoes));
    // Decoderen en bakken gebeuren buiten de nagebootste klok.
    for (var i = 0; i < 5; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    final binnen = find.descendant(of: find.byType(HoesAchtergrond), matching: find.byType(RawImage));
    expect(binnen, findsOneWidget, reason: 'de hoes is niet gebakken, of komt niet in beeld');
    expect(t.widget<RawImage>(binnen).image, isNotNull);
    for (final duur in [ImageFiltered, ShaderMask, BackdropFilter]) {
      expect(find.descendant(of: find.byType(HoesAchtergrond), matching: find.byType(duur)),
          findsNothing,
          reason: '$duur wordt onder Impeller elk beeld opnieuw getekend — op de telefoon miste '
              'scrollen daardoor 10–11 beelden per ronde');
    }
  });

  group('het gebakken beeld', () {
    const vak = Size(200, 300);

    testWidgets('DE KERN: hetzelfde als de vervaging en het masker die er per beeld stonden', (t) async {
      final bron = (await t.runAsync(_ruitjes))!;
      final oud = (await t.runAsync(() async => _pixels(await _oudeOpbouw(t, bron, vak))))!;
      final nieuw = (await t.runAsync(
          () async => _pixels(await bakHoesAchtergrond(bron, vak: vak, schaal: 1))))!;
      expect(nieuw.length, oud.length, reason: 'het gebakken beeld heeft een andere maat');
      var grootste = 0, som = 0;
      for (var i = 0; i < oud.length; i++) {
        final v = (oud[i] - nieuw[i]).abs();
        som += v;
        if (v > grootste) grootste = v;
      }
      final gemiddeld = som / oud.length;
      // Gemeten op 05-10-2026: 0 en 0, byte voor byte gelijk. De marge is voor afronding elders.
      expect(gemiddeld, lessThan(.5),
          reason: 'het gebakken beeld wijkt gemiddeld $gemiddeld af van wat er stond');
      expect(grootste, lessThanOrEqualTo(4),
          reason: 'het gebakken beeld wijkt ergens $grootste af van wat er stond');
    });

    testWidgets('DE GRENS: onderaan lost hij op, bovenaan is hij dicht', (t) async {
      final bron = (await t.runAsync(_ruitjes))!;
      for (final schaal in [1.0, .5]) {
        final b = (await t.runAsync(() => bakHoesAchtergrond(bron, vak: vak, schaal: schaal)))!;
        final px = (await t.runAsync(() => _pixels(b)))!;
        int alfa(double fx, double fy) =>
            px[(((b.height - 1) * fy).round() * b.width + ((b.width - 1) * fx).round()) * 4 + 3];
        // De onderste rij wordt in het midden van de pixel gemeten, net boven de 0 van het verloop.
        expect(alfa(.5, 1), lessThanOrEqualTo(2),
            reason: 'onderaan hoort er niets meer van over te zijn, anders loopt er een streep');
        expect(alfa(.5, .3), 255, reason: 'midden in de kop is de waas dicht (schaal $schaal)');
        expect(alfa(.5, 0), greaterThan(170),
            reason: 'bovenaan zit de donkering er altijd, ook waar de vervaging dunner wordt');
        expect(b.width, (vak.width * schaal).ceil(),
            reason: 'de schaal bepaalt de maat van het gebakken beeld');
      }
    });
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

/// Een hoes met vlakken en randen, zodat een verkeerde vervaging of uitsnede ook iets te verschuiven
/// heeft: vier gekleurde kwadranten met een witte balk erdoor.
Future<ui.Image> _ruitjes() {
  final r = ui.PictureRecorder();
  final c = Canvas(r);
  const n = 128.0;
  c.drawRect(const Rect.fromLTWH(0, 0, n / 2, n / 2), Paint()..color = const Color(0xFFD03030));
  c.drawRect(const Rect.fromLTWH(n / 2, 0, n / 2, n / 2), Paint()..color = const Color(0xFF3060D0));
  c.drawRect(const Rect.fromLTWH(0, n / 2, n / 2, n / 2), Paint()..color = const Color(0xFF30B050));
  c.drawRect(const Rect.fromLTWH(n / 2, n / 2, n / 2, n / 2), Paint()..color = const Color(0xFFE0C040));
  c.drawRect(const Rect.fromLTWH(0, n * .45, n, n * .1), Paint()..color = const Color(0xFFFFFFFF));
  return r.endRecording().toImage(n.toInt(), n.toInt());
}

/// Wat er tot 05-10-2026 per beeld getekend werd, letterlijk overgenomen, als vergelijking.
Future<ui.Image> _oudeOpbouw(WidgetTester t, ui.Image bron, Size vak) async {
  final sleutel = GlobalKey();
  await t.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: sleutel,
        child: SizedBox.fromSize(
          size: vak,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: HoesAchtergrond.vervloeiing.createShader,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRect(
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: HoesAchtergrond.sigma, sigmaY: HoesAchtergrond.sigma),
                    child: Transform.scale(
                      scale: HoesAchtergrond.uitvergroting,
                      child: RawImage(image: bron, fit: BoxFit.cover, filterQuality: FilterQuality.low),
                    ),
                  ),
                ),
                const ColoredBox(color: HoesAchtergrond.donkering),
              ],
            ),
          ),
        ),
      ),
    ),
  ));
  final rb = t.renderObject<RenderRepaintBoundary>(find.byKey(sleutel));
  return rb.toImage();
}

Future<Uint8List> _pixels(ui.Image b) async =>
    (await b.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();

/// Een geldige 1×1 PNG: klein genoeg om in een toets te staan, echt genoeg om te decoderen.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
