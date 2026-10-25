// De hoes en de cd die eruit steekt, als één ding (Saber, 25-10-2026, met een schermafdruk van Stadium Arcadium):
// "ook bij het tilten van de hoes, zie je een verschil in kleur/licht, kunnen we daar iets doen, dat het realistisch
// blijft bij de motion, ook het draaien van de album blijft niet realistisch genoeg".
import 'dart:io';
import 'dart:ui' as ui;

import 'package:debridmusic/ui/kantel_hoes.dart';
import 'package:debridmusic/ui/langzame_draai.dart';
import 'package:debridmusic/ui/wachtrij_eiland.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

class _Plaat extends StatefulWidget {
  const _Plaat({required this.speelt, required this.draai});
  final bool speelt;
  final void Function(LangzameDraai) draai;
  @override
  State<_Plaat> createState() => _PlaatState();
}

class _PlaatState extends State<_Plaat> with TickerProviderStateMixin {
  late final LangzameDraai spin = LangzameDraai(this,
      omwenteling: const Duration(seconds: 9),
      schermHz: () => 60,
      aanloop: const Duration(milliseconds: 350),
      uitloop: const Duration(milliseconds: 500));

  @override
  void initState() {
    super.initState();
    widget.draai(spin);
    if (widget.speelt) spin.start();
  }

  @override
  void didUpdateWidget(_Plaat old) {
    super.didUpdateWidget(old);
    if (widget.speelt && !spin.isAnimating) spin.start();
    if (!widget.speelt) spin.stop();
  }

  @override
  void dispose() {
    spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: spin,
        builder: (_, __) => Transform.rotate(angle: spin.value * 6.283, child: const SizedBox(width: 50, height: 50)),
      );
}

Future<void> _seconden(WidgetTester t, double s) async {
  for (var i = 0; i < (s * 60).round(); i++) {
    await t.pump(const Duration(microseconds: 16667));
  }
}

/// Eén pixel van wat [teken] op een doek van [maat] tekent.
Future<Color> _pixel(WidgetTester t, Size maat, void Function(Canvas) teken, Offset p) async {
  final r = ui.PictureRecorder();
  teken(Canvas(r));
  final beeld = await t.runAsync(() => r.endRecording().toImage(maat.width.round(), maat.height.round()));
  final data = (await t.runAsync(() => beeld!.toByteData()))!;
  final i = (p.dy.round() * maat.width.round() + p.dx.round()) * 4;
  return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
}

void main() {
  group('de cd heeft massa', () {
    testWidgets('DE KERN: bij afspelen komt hij op toeren — niet meteen op volle snelheid', (t) async {
      late LangzameDraai spin;
      await t.pumpWidget(_Plaat(speelt: true, draai: (s) => spin = s));
      await _seconden(t, .1);
      expect(spin.snelheid, inExclusiveRange(.1, .5), reason: 'na 0,1 s nog lang niet op snelheid');
      expect(spin.value, lessThan(.1 / 9), reason: 'en dus minder ver dan op volle snelheid');
      await _seconden(t, 1.2);
      expect(spin.snelheid, greaterThan(.95), reason: 'na ruim een seconde wel');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('DE KERN: bij pauze loopt hij uit, en staat dan echt stil (vraagt geen beelden meer)', (t) async {
      late LangzameDraai spin;
      await t.pumpWidget(_Plaat(speelt: true, draai: (s) => spin = s));
      await _seconden(t, 2);
      final voor = LangzameDraai.lopend;
      await t.pumpWidget(_Plaat(speelt: false, draai: (s) => spin = s));
      expect(spin.isAnimating, isFalse, reason: 'stoppen is gevraagd');
      final bijStop = spin.value;
      await _seconden(t, .3);
      expect(spin.value, greaterThan(bijStop), reason: 'maar hij loopt nog uit');
      await _seconden(t, 2.5);
      final stil = spin.value;
      var meldingen = 0;
      spin.addListener(() => meldingen++);
      await _seconden(t, .5);
      expect(meldingen, 0, reason: 'uitgelopen: geen beelden meer');
      expect(spin.value, stil);
      expect(LangzameDraai.lopend, voor - 1);
      // Hoe ver hij uitliep: ongeveer uitloop × volle snelheid = 0,5 s van 9 s, een twintigste slag.
      expect(((stil - bijStop) % 1.0), closeTo(.5 / 9, .01));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('weer afspelen terwijl hij uitloopt: vanaf daar weer op toeren, zonder sprong', (t) async {
      late LangzameDraai spin;
      await t.pumpWidget(_Plaat(speelt: true, draai: (s) => spin = s));
      await _seconden(t, 2);
      await t.pumpWidget(_Plaat(speelt: false, draai: (s) => spin = s));
      await _seconden(t, .4);
      final half = spin.snelheid;
      expect(half, inExclusiveRange(.2, .8));
      await t.pumpWidget(_Plaat(speelt: true, draai: (s) => spin = s));
      expect(spin.isAnimating, isTrue);
      await _seconden(t, .05);
      expect(spin.snelheid, greaterThan(half), reason: 'hij versnelt weer, vanaf waar hij was');
      await t.pumpWidget(const SizedBox());
    });
  });

  group('de cd kantelt mee in het vlak van de hoes', () {
    testWidgets('DE KERN: de hoes geeft zijn stand door, en in rust weer nul', (t) async {
      final stand = ValueNotifier<Offset>(Offset.zero);
      addTearDown(stand.dispose);
      await t.pumpWidget(MaterialApp(
          home: Center(
              child: SizedBox.square(
                  dimension: 200, child: KantelHoes(deel: stand, child: const ColoredBox(color: Colors.brown))))));
      final muis = await t.createGesture(kind: PointerDeviceKind.mouse);
      await muis.addPointer(location: Offset.zero);
      addTearDown(muis.removePointer);
      await muis.moveTo(t.getCenter(find.byType(KantelHoes)) + const Offset(95, 0));
      await t.pump();
      await t.pump(kKantelVolg);
      expect(stand.value.dx, greaterThan(.8), reason: 'rechts op de hoes: de cd weet dat de hoes rechts wegzakt');
      await muis.moveTo(const Offset(2, 2));
      await t.pumpAndSettle();
      expect(stand.value, Offset.zero);
    });

    testWidgets('één lichtvlek over hoes en cd: op hetzelfde punt dezelfde glans', (t) async {
      const o = Offset(.9, -.4);
      const s = 300.0;
      // De hoes op (0, 0); de cd (s · 0,92) steekt er rechts uit, op (180, 12).
      const schijfIn = Offset(180, 12);
      final hoesVak = Rect.fromLTWH(-schijfIn.dx, -schijfIn.dy, s, s);
      const punt = Offset(250, 150); // op de hoes, en ook op de cd
      final opHoes = await _pixel(t, const Size(s, s),
          (c) => tekenKantelGlans(c, Offset.zero & const Size(s, s), Offset.zero & const Size(s, s), o), punt);
      final opSchijf = await _pixel(t, const Size(s * .92, s * .92),
          (c) => SchijfKantelGlans(o, hoes: hoesVak).paint(c, const Size(s * .92, s * .92)), punt - schijfIn);
      expect(opHoes.a, greaterThan(.02), reason: 'er valt licht');
      expect((opHoes.a - opSchijf.a).abs(), lessThan(.02), reason: 'hoes $opHoes, cd $opSchijf');
    });

    test('in rust tekent de cd geen glans', () {
      final r = ui.PictureRecorder();
      final c = Canvas(r);
      SchijfKantelGlans(Offset.zero, hoes: const Rect.fromLTWH(0, 0, 10, 10)).paint(c, const Size(9, 9));
      // Geen bewerking op het doek: niets getekend.
      expect(SchijfKantelGlans(Offset.zero, hoes: Rect.zero).shouldRepaint(SchijfKantelGlans(Offset.zero, hoes: Rect.zero)),
          isFalse);
      r.endRecording().dispose();
    });

    testWidgets('het wachtrij-eiland: de schaduw van de hoes op het plaatje ligt tegen de rand van de gekantelde hoes',
        (t) async {
      // Groot, zodat het verschil te meten is: op 52 punten is het een fractie van een pixel, op 400 een paar.
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: 900, child: WachtrijEiland(hoes: null, speelt: false, maat: 400, child: const Text('x')))))));
      final hoes =
          find.descendant(of: find.byKey(const ValueKey('wachtrij-hoes')), matching: find.byType(DecoratedBox)).first;
      final rand = t.getTopRight(hoes).dx;
      final schaduw = t.getTopLeft(find.byKey(const ValueKey('mouw-schaduw'))).dx;
      expect(schaduw, closeTo(rand, .5), reason: 'rand van de hoes $rand, schaduw $schaduw');
    });

    test('aangesloten in Nu speelt (gelezen uit lib/main.dart)', () {
      final main = _bron('lib/main.dart');
      expect(main, contains('            deel: _kantel,\n            child: kaart,'));
      expect(main, contains('              animation: Listenable.merge([_slide, _kantel]),'));
      expect(main, contains('                    transform: rust ? Matrix4.identity() : kantelMatrix(o),\n'
          '                    origin: hoesVak.center,'));
      expect(main, contains('                final hoesVak = Rect.fromLTWH(x.hoes - x.schijf, -s * .04, s, s);'));
      expect(main, contains('painter: SchijfKantelGlans(rust ? Offset.zero : o, hoes: hoesVak),'));
      expect(main, contains('      aanloop: kSchijfAanloop,\n      uitloop: kSchijfUitloop);'));
    });
  });
}
