// Het lichte thema op de tv zoals op de pc en de gsm (Saber, 19-10-2026: "probeer nog eens het light
// thema ook op shield, maar volledig zoals het is op pc en gsm"). Naast elkaar gelegd op de Shield, de
// pc en de S26 waren er vijf verschillen, alle vijf een uitzondering voor de tv in de code:
// zwarte letters op de glazen knoppen (paars op pc en gsm), een bruinroze band door de menucapsule,
// een dichte spelerbalk op de volle tint met een streep erboven, geen spiegeling onder de grote hoes,
// en geen vervaagde hoes achter Nu speelt.
import 'dart:io';

import 'package:debridmusic/artwork.dart' show HoesVlek;
import 'package:debridmusic/main.dart' show balkOpTvLicht, gevuldeKnopStijl, kTvKnopGlas;
import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/glas.dart';
import 'package:debridmusic/ui/kleuren.dart';
import 'package:debridmusic/ui/vlak.dart' show GlasKnop, balkKleur;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget kind) => MaterialApp(home: Scaffold(body: Center(child: kind)));

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  tearDown(() {
    setTvModeForTest(false);
    Thema.licht = false;
    GlasKwaliteit.vergeet();
  });

  group('de glazen knop', () {
    for (final tv in [true, false]) {
      testWidgets('licht, ${tv ? 'tv' : 'pc'}: paarse letters, zoals op pc en gsm', (t) async {
        setTvModeForTest(tv);
        Thema.licht = true;
        await t.pumpWidget(_app(GlasKnop(icoon: Icons.radio_rounded, label: 'Radio', onPressed: () {})));
        final stijl = t.widget<FilledButton>(find.byType(FilledButton)).style!;
        expect(stijl.foregroundColor!.resolve({}), kAccent);
      });
    }

    testWidgets('donker op de tv: wit, zoals altijd', (t) async {
      setTvModeForTest(true);
      await t.pumpWidget(_app(GlasKnop(icoon: Icons.radio_rounded, label: 'Radio', onPressed: () {})));
      final stijl = t.widget<FilledButton>(find.byType(FilledButton)).style!;
      expect(stijl.foregroundColor!.resolve({}), Colors.white);
    });

    // 24-10-2026, "Radio afsluiten" op de Shield: de knop "91 naar de prullenbak" was een lege paarse balk — paarse
    // letters ([_focusOutlineGevuld]) op Materials paarse vulling. Nu is de vulling op de tv glas.
    for (final licht in [true, false]) {
      test('een gevulde knop zonder eigen vulling, tv ${licht ? 'licht' : 'donker'}: letters nooit in de kleur van de vulling',
          () {
        setTvModeForTest(true);
        Thema.licht = licht;
        final stijl = gevuldeKnopStijl;
        for (final s in [<WidgetState>{}, {WidgetState.focused}]) {
          final vulling = stijl.backgroundColor!.resolve(s);
          expect(vulling, kTvKnopGlas, reason: 'glas, zoals de andere knoppen op de tv');
          final letters = stijl.foregroundColor!.resolve(s) ?? Colors.white;
          expect(letters, isNot(vulling));
          expect(vulling, isNot(kAccent), reason: 'paarse letters op paars: een lege balk');
          expect(letters.a, greaterThan(.9), reason: 'letters die je ziet');
        }
        setTvModeForTest(false);
        expect(gevuldeKnopStijl.backgroundColor!.resolve({}), isNull, reason: 'op de pc en de gsm: Materials vulling');
      });
    }

    test('de glazen knoppen met de vulling van de tv: in licht ook paars', () {
      final main = _bron('lib/main.dart');
      final i = main.indexOf('final ButtonStyle _focusOutlineGevuld');
      expect(i, greaterThan(0));
      expect(main.substring(i, i + 400), contains('return Thema.licht ? kAccent : null;'));
    });
  });

  group('de menucapsule op de tv', () {
    Widget capsule() => const SizedBox(
        width: 400,
        height: 60,
        child: GlasVlak(
            vorm: BorderRadius.all(Radius.circular(30)),
            kleur: Color(0xFFF7F4EE),
            lens: true,
            balk: true,
            child: SizedBox.expand()));

    testWidgets('licht: geen vlekken uit de hoes, schoon zoals op de pc', (t) async {
      setTvModeForTest(true);
      Thema.licht = true;
      GlasKwaliteit.micaVlekken.value = const [HoesVlek(.5, .5, 0xFFCC2222, 1)];
      await t.pumpWidget(_app(capsule()));
      expect(find.byType(HoesVlekkenLaag), findsNothing);
    });

    testWidgets('donker: de vlekken blijven (het nep-glas van 18-10-2026)', (t) async {
      setTvModeForTest(true);
      GlasKwaliteit.micaVlekken.value = const [HoesVlek(.5, .5, 0xFFCC2222, 1)];
      await t.pumpWidget(_app(capsule()));
      expect(find.byType(HoesVlekkenLaag), findsOneWidget);
    });
  });

  group('de spelerbalk op de tv in licht', () {
    setUp(() => Thema.licht = true);

    test('de kleur van de glazen balk op de pc: 85 % tint over de pagina, dicht', () {
      const kelis = 0xFFCC2222;
      final c = balkOpTvLicht(kelis);
      expect(c.a, 1, reason: 'dicht: de Shield vervaagt niets');
      expect(c, Color.alphaBlend(balkKleur(kelis).withValues(alpha: kGlasDekking), kAchtergrond));
      // Lichter dan de volle tint: dichter bij de pagina.
      double afstand(Color a, Color b) => (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
      expect(afstand(c, kAchtergrond), lessThan(afstand(balkKleur(kelis), kAchtergrond)));
    });

    test('aangesloten: op een tv in licht die kleur en geen streep erboven', () {
      final main = _bron('lib/main.dart');
      expect(main, contains('            : isTv && Thema.licht\n                ? balkOpTvLicht(x.player.wasKleur)\n'));
      expect(main, contains('border: opGlas || (isTv && Thema.licht) ? null : Border(top: BorderSide(color: _line)),'));
    });
  });

  test('aangesloten: de spiegeling en de vervaagde hoes van Nu speelt ook op een tv', () {
    final main = _bron('lib/main.dart');
    expect(main, isNot(contains('spiegel: !isTv')));
    expect(main, contains('spiegel: true,\n'), reason: 'de albumpagina');
    expect(main, contains('spiegel: !dwars && !stapelAan,'), reason: 'Nu speelt');
    final achter = main.indexOf("key: const Key('np-hoes-achter'),");
    expect(achter, greaterThan(0));
    expect(main.substring(achter - 900, achter), contains('if (p.currentCover != null) ...['));
    expect(main.substring(achter - 900, achter), isNot(contains('!isTv')));
  });
}
