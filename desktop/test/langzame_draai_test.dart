/// De draaiende plaat vraagt zestig beelden per seconde, gelijkmatig — niet honderdtwintig.
///
/// Gemeten op 05-10-2026 op Sabers S26 aan de kabel: "Now playing" met een spelende plaat tekende
/// 14.403 beelden in twee minuten, terwijl de plaat in negen seconden één keer ronddraait. De
/// batterij liep aan de lader leeg (−0,41 tot −0,86 A tegen +0,33 A gepauzeerd), de telefoon werd
/// 36 °C en remde zichzelf af, en het notificatiescherm en het draaien naar liggend haperden. Saber:
/// *"de now playing, die is zwaar, en happerd, ook als je drawer naar beneden doet"*.
///
/// Deze toets doet een scherm van 120 Hz na en telt hoeveel beelden de plaat AANVRAAGT — wat er
/// getekend wordt hangt daarvan af, en op het toestel is dat precies wat de batterij kost.
library;

import 'dart:io';

import 'package:debridmusic/ui/langzame_draai.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een plaat die draait, zoals in `AlbumArt`.
class _Plaat extends StatefulWidget {
  const _Plaat({required this.speelt, required this.draai, this.hz = 120, this.max = 60});
  final bool speelt;
  final double hz;
  final int max;
  final void Function(LangzameDraai) draai;
  @override
  State<_Plaat> createState() => _PlaatState();
}

class _PlaatState extends State<_Plaat> with TickerProviderStateMixin {
  // Een scherm van 120 Hz, zoals de S26 — de toets doet hieronder ook 120 Hz na.
  late final LangzameDraai spin =
      LangzameDraai(this,
          omwenteling: const Duration(seconds: 9), schermHz: () => widget.hz, maxBeeldenPerSeconde: widget.max);

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
        builder: (_, __) => Transform.rotate(angle: spin.value * 6.283, child: const SizedBox(width: 100, height: 100)),
      );
}

/// [seconden] lang een scherm van 120 Hz nadoen, en tellen hoe vaak [l] een nieuw beeld nodig had.
/// Elke melding is een hertekening — en op het toestel een getekend beeld.
Future<int> _scherm120(WidgetTester tester, double seconden, Listenable l) async {
  var tikken = 0;
  void tel() => tikken++;
  l.addListener(tel);
  final n = (seconden * 120).round();
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(microseconds: 8333));
  }
  l.removeListener(tel);
  return tikken;
}

/// De oude manier, als ijkpunt in dezelfde nagedane 120 Hz.
class _Oud extends StatefulWidget {
  const _Oud({required this.draai});
  final void Function(AnimationController) draai;
  @override
  State<_Oud> createState() => _OudState();
}

class _OudState extends State<_Oud> with SingleTickerProviderStateMixin {
  late final AnimationController spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();
  @override
  void initState() {
    super.initState();
    widget.draai(spin);
  }

  @override
  void dispose() {
    spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('DE KERN: op een scherm van 120 Hz vraagt de plaat 60 beelden per seconde, niet 120',
      (tester) async {
    late LangzameDraai spin;
    await tester.pumpWidget(_Plaat(speelt: true, draai: (s) => spin = s));
    final gevraagd = await _scherm120(tester, 3, spin);
    expect(gevraagd, inInclusiveRange(170, 185), reason: 'zestig per seconde, en niet het schermritme');
    // En hij draait wel echt: 3 van de 9 seconden is een derde slag.
    expect(spin.value, closeTo(1 / 3, .03), reason: 'de plaat moet even snel draaien als voorheen');
    await tester.pumpWidget(const SizedBox());
  });

  // Op het toestel gemeten in 3.9.441, met een vaste marge van 4 ms: 42 beelden per seconde, maar om
  // en om na 8, 29, 33 en 42 ms. Dat zag Saber als haperen — "de staande is nu de cd niet vloeiend".
  testWidgets('DE VAL: gelijkmatig — elke tweede schermtik, niet om en om kort en lang', (tester) async {
    late LangzameDraai spin;
    await tester.pumpWidget(_Plaat(speelt: true, draai: (s) => spin = s));
    final tijden = <Duration>[];
    void noteer() => tijden.add(SchedulerBinding.instance.currentFrameTimeStamp);
    spin.addListener(noteer);
    for (var i = 0; i < 240; i++) {
      await tester.pump(const Duration(microseconds: 8333));
    }
    spin.removeListener(noteer);
    final afstanden = [
      for (var i = 2; i < tijden.length; i++) (tijden[i] - tijden[i - 1]).inMicroseconds / 1000
    ];
    final gelijk = afstanden.where((ms) => ms > 15 && ms < 18.5).length;
    expect(gelijk / afstanden.length, greaterThan(.95),
        reason: 'afstanden: ${afstanden.map((a) => a.toStringAsFixed(1)).toSet().join(', ')} ms');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ijkpunt: de oude AnimationController vroeg er in dezelfde nadoening 120 per seconde', (tester) async {
    late AnimationController oud;
    await tester.pumpWidget(_Oud(draai: (c) => oud = c));
    expect(await _scherm120(tester, 3, oud), greaterThan(340),
        reason: 'zo maakte "Now playing" er 14.403 in twee minuten, op het toestel gemeten');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('DE VAL: gestopt vraagt hij niets meer — en er blijft geen klok achter', (tester) async {
    late LangzameDraai spin;
    await tester.pumpWidget(_Plaat(speelt: true, draai: (s) => spin = s));
    await _scherm120(tester, .5, spin);
    await tester.pumpWidget(_Plaat(speelt: false, draai: (_) {}));
    await tester.pump();
    expect(await _scherm120(tester, 1, spin), 0, reason: 'een stilstaande plaat vraagt geen beelden');
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'ook geen lege: een tikker die doorloopt zonder iets te melden kost op het toestel net zo goed beelden');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('DE GRENS: achter een andere pagina (TickerMode uit) vraagt hij niets', (tester) async {
    late LangzameDraai spin;
    await tester.pumpWidget(TickerMode(enabled: false, child: _Plaat(speelt: true, draai: (s) => spin = s)));
    await tester.pump();
    expect(await _scherm120(tester, 1, spin), 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('na een lange pauze springt de plaat niet een eind verder', (tester) async {
    late LangzameDraai spin;
    await tester.pumpWidget(_Plaat(speelt: true, draai: (s) => spin = s));
    await _scherm120(tester, .2, spin);
    final voor = spin.value;
    // Een minuut geen beeld (de app lag in de achtergrond), dan weer één.
    await tester.pump(const Duration(minutes: 1));
    await tester.pump(const Duration(milliseconds: 40));
    expect((spin.value - voor + 1) % 1, lessThan(.07), reason: 'hooguit een halve seconde verder');
    await tester.pumpWidget(const SizedBox());
  });

  // Saber, 05-10-2026: "ik heb een refresh rate beeld van msi die tot 144ghz gaat". Met een vast doel
  // van 60 viel 144 Hz om en om op 2 en 3 schermtikken; fps.log op de pc gaf 49 tot 53 per seconde.
  for (final (naam, hz, max, perSeconde) in [
    ('telefoon op 144 Hz: elke 2e tik', 144.0, 60, 72),
    ('telefoon op 60 Hz: elke tik', 60.0, 60, 60),
    ('pc op 144 Hz: elke tik', 144.0, 1000, 144),
  ]) {
    testWidgets('DE GRENS ($naam): $perSeconde per seconde, gelijkmatig', (tester) async {
      late LangzameDraai spin;
      await tester.pumpWidget(_Plaat(speelt: true, hz: hz, max: max, draai: (s) => spin = s));
      final tijden = <Duration>[];
      void noteer() => tijden.add(SchedulerBinding.instance.currentFrameTimeStamp);
      spin.addListener(noteer);
      final tik = Duration(microseconds: (1e6 / hz).round());
      final n = (2 * hz).round();
      for (var i = 0; i < n; i++) {
        await tester.pump(tik);
      }
      spin.removeListener(noteer);
      expect(tijden.length / 2, closeTo(perSeconde, perSeconde * .05),
          reason: 'beelden per seconde op ${hz.round()} Hz');
      final verwacht = 1000 / perSeconde;
      final afstanden = [
        for (var i = 2; i < tijden.length; i++) (tijden[i] - tijden[i - 1]).inMicroseconds / 1000
      ];
      expect(afstanden.where((ms) => (ms - verwacht).abs() < 1.2).length / afstanden.length, greaterThan(.95),
          reason: 'afstanden: ${afstanden.map((a) => a.toStringAsFixed(1)).toSet().join(', ')} ms');
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('de plaat in de app gebruikt deze draaier', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('late final LangzameDraai _spin = LangzameDraai(this,'));
    expect(main, contains('maxBeeldenPerSeconde: _isDesktop ? 1000 : 60'),
        reason: 'op de pc elke schermtik, op een telefoon hooguit 60');
    expect(main, isNot(contains('AnimationController(vsync: this, duration: const Duration(seconds: 9))')),
        reason: 'een AnimationController vraagt elk schermbeeld aan');
  });
}
