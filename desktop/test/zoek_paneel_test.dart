import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/ui/zoek_paneel.dart';
import 'package:debridmusic/zoek_suggesties.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Het glazen paneel: open en dicht, de pijltjes, de Shield, en wat er vliegt.
Track nr(String a, String p, String t) => Track(path: 'D:/m/$a/$p/$t.flac', title: t, artist: a, album: p, trackNo: 1, isFlac: true);
Album plaat(String a, String t, List<String> n) => Album(t, a, [for (final x in n) nr(a, t, x)]);

final bib = [
  plaat('Khaled', 'Sahra', ['Aïcha']),
  plaat('Adele', '21', ['Rolling in the Deep']),
];

class Proef {
  final ctl = TextEditingController();
  final focus = FocusNode();
  final stuur = ZoekPaneelStuur();
  final recent = ZoekRecent();
  late final bron = SuggestieBron(
    albums: () => bib,
    online: (q) async => OnlineTreffers([CatalogArtist(9, 'DJ Khaled', null, 3)], const [], const []),
    eigenPauze: const Duration(milliseconds: 1),
    onlinePauze: const Duration(milliseconds: 1),
  );
  final gekozen = <String>[];
  final gezocht = <String>[];
  final oud = <String>[];
  var enter = 0;
}

Future<Proef> bouw(WidgetTester t, {bool tv = false, bool inline = false, Size scherm = const Size(390, 800), bool rustig = false}) async {
  t.view.physicalSize = scherm;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final p = Proef();
  addTearDown(() {
    p.bron.dispose();
    p.stuur.dispose();
    p.ctl.dispose();
    p.focus.dispose();
  });
  await t.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: scherm, disableAnimations: rustig),
      child: Scaffold(
        body: Column(children: [
          const SizedBox(height: 40),
          ZoekSuggesties(
            controller: p.ctl,
            focus: p.focus,
            bron: p.bron,
            recent: p.recent,
            stuur: p.stuur,
            tv: tv,
            inline: inline,
            klein: true,
            beeld: (_, s, m) => SizedBox(key: ValueKey('beeld:${s.titel}'), width: m, height: m),
            opKies: (s, _, __) => p.gekozen.add(s.titel),
            opZoek: p.gezocht.add,
            zoekTekst: (x) => 'Zoek online op “$x”',
            opRecent: p.oud.add,
            child: TextField(
              key: const ValueKey('veld'),
              controller: p.ctl,
              focusNode: p.focus,
              groupId: p.stuur.groep,
              onSubmitted: (_) => p.enter++,
            ),
          ),
          const Expanded(child: Center(child: Text('de lijst eronder'))),
        ]),
      ),
    ),
  ));
  return p;
}

Future<void> typ(WidgetTester t, String tekst) async {
  await t.tap(find.byKey(const ValueKey('veld')));
  await t.pump();
  await t.enterText(find.byKey(const ValueKey('veld')), tekst);
  await t.pump(const Duration(milliseconds: 10));
  await t.pump(const Duration(milliseconds: 10));
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('typen opent het paneel met je bibliotheek en Deezer, met onderaan zoek online', (t) async {
    await bouw(t);
    await typ(t, 'khaled');
    expect(find.text('ARTIESTEN'), findsOneWidget);
    expect(find.text('Zoek online op “khaled”'), findsOneWidget);
    expect(find.byKey(const ValueKey('beeld:Khaled')), findsOneWidget);
    expect(find.byKey(const ValueKey('beeld:DJ Khaled')), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsWidgets, reason: 'wat van jou is, heeft een vinkje');
    expect(find.byIcon(Icons.download_rounded), findsWidgets, reason: 'wat online staat, niet');
    expect(t.takeException(), isNull);
  });

  testWidgets('een tik op een rij kiest hem', (t) async {
    final p = await bouw(t);
    await typ(t, 'khaled');
    await t.tap(find.byKey(const ValueKey('beeld:DJ Khaled')));
    await t.pump();
    expect(p.gekozen, ['DJ Khaled']);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('een tik op de zoekrij zoekt op wat er staat', (t) async {
    final p = await bouw(t);
    await typ(t, 'khalid');
    await t.tap(find.text('Zoek online op “khalid”'));
    await t.pump();
    expect(p.gezocht, ['khalid']);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('naast tikken sluit het paneel, en de lijst eronder is er nog', (t) async {
    final p = await bouw(t);
    await typ(t, 'khaled');
    expect(find.text('ARTIESTEN'), findsOneWidget);
    await t.tapAt(const Offset(195, 780));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('ARTIESTEN'), findsNothing);
    expect(find.text('de lijst eronder'), findsOneWidget);
    expect(p.ctl.text, 'khaled', reason: 'wat je typte blijft staan');
  });

  testWidgets('verder typen opent het weer', (t) async {
    final p = await bouw(t);
    await typ(t, 'khaled');
    p.stuur.sluit();
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pump();
    expect(find.text('ARTIESTEN'), findsNothing);
    await t.enterText(find.byKey(const ValueKey('veld')), 'khaled ');
    await t.enterText(find.byKey(const ValueKey('veld')), 'khaled a');
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Zoek online op “khaled a”'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('pijltjes wijzen aan, Enter kiest; zonder aanwijzen is Enter gewoon van het veld', (t) async {
    final p = await bouw(t);
    await typ(t, 'adele');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump(const Duration(milliseconds: 200));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(p.gekozen, ['Adele']);
    expect(p.enter, 0, reason: 'de Enter was van de rij');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump(const Duration(milliseconds: 200));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(p.gekozen, ['Adele'], reason: 'niets aangewezen');
    expect(p.enter, 1);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('Escape sluit eerst het paneel, en is daarna van wie erom heen staat', (t) async {
    final p = await bouw(t);
    await typ(t, 'adele');
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pump();
    expect(p.stuur.dicht, isTrue);
    expect(find.text('Zoek online op “adele”'), findsNothing);
    expect(p.focus.hasFocus, isTrue);
  });

  testWidgets('leeg veld: je laatste zoekopdrachten, met een kruisje', (t) async {
    final p = await bouw(t);
    p.recent.voegToe('rihanna');
    p.recent.voegToe('sade');
    await t.tap(find.byKey(const ValueKey('veld')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('LAATST GEZOCHT'), findsOneWidget);
    await t.tap(find.text('sade'));
    await t.pump();
    expect(p.oud, ['sade']);
    await t.tap(find.byIcon(Icons.close_rounded).first);
    await t.pump(const Duration(milliseconds: 400));
    expect(p.recent.lijst, ['rihanna']);
    expect(find.text('sade'), findsNothing);
  });

  testWidgets('leeg veld zonder oude zoekopdrachten: geen paneel', (t) async {
    await bouw(t);
    await t.tap(find.byKey(const ValueKey('veld')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('LAATST GEZOCHT'), findsNothing);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('het paneel past op het scherm, ook heel smal en met het toetsenbord erbij', (t) async {
    await bouw(t, scherm: const Size(320, 480));
    await typ(t, 'khaled');
    expect(t.takeException(), isNull);
    final r = t.getRect(find.byType(ListView));
    expect(r.right, lessThanOrEqualTo(320));
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.bottom, lessThanOrEqualTo(480));
  });

  testWidgets('zonder animaties is het er meteen, zonder fout', (t) async {
    await bouw(t, rustig: true);
    await typ(t, 'khaled');
    expect(find.text('ARTIESTEN'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  group('de Shield', () {
    testWidgets('de zoekrij staat vooraan, en naarEerste wijst hem aan', (t) async {
      final p = await bouw(t, tv: true, scherm: const Size(1920, 1080));
      await typ(t, 'khaled');
      final zoek = t.getTopLeft(find.text('Zoek online op “khaled”'));
      final khaled = t.getTopLeft(find.byKey(const ValueKey('beeld:Khaled')));
      expect(zoek.dy, lessThan(khaled.dy), reason: 'OK op het toetsenbord en nog eens OK zoekt gewoon');
      expect(p.stuur.naarEerste(), isTrue);
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(p.focus.hasFocus, isFalse);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pump();
      expect(p.gezocht, ['khaled']);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('het paneel blijft open als de focus op een rij staat, en Terug gaat naar het veld', (t) async {
      final p = await bouw(t, tv: true, scherm: const Size(1920, 1080));
      await typ(t, 'khaled');
      p.stuur.naarEerste();
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('ARTIESTEN'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(p.stuur.dicht, isTrue);
      expect(p.focus.hasFocus, isTrue);
    });

    testWidgets('pijltje rechts loopt door het raster: drie op een rij', (t) async {
      final p = await bouw(t, tv: true, scherm: const Size(1920, 1080));
      await typ(t, 'khaled');
      p.stuur.naarEerste();
      await t.pump(const Duration(milliseconds: 200));
      final a = t.getTopLeft(find.byKey(const ValueKey('beeld:Khaled')));
      final b = t.getTopLeft(find.byKey(const ValueKey('beeld:DJ Khaled')));
      expect(a.dy, b.dy, reason: 'naast elkaar');
      expect(b.dx - a.dx, greaterThan(400), reason: 'een derde van de breedte');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump(const Duration(milliseconds: 100));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump(const Duration(milliseconds: 100));
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pump();
      expect(p.gekozen, ['DJ Khaled']);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('in de dialoog staat het raster gewoon onder het veld', (t) async {
      await bouw(t, tv: true, inline: true, scherm: const Size(1920, 1080));
      await typ(t, 'adele');
      expect(find.text('Zoek online op “adele”'), findsOneWidget);
      expect(t.getTopLeft(find.text('Zoek online op “adele”')).dy, greaterThan(t.getBottomLeft(find.byKey(const ValueKey('veld'))).dy));
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('de terugknop sluit eerst een open paneel, en daarna is hij weer van de app', (t) async {
    final p = await bouw(t);
    await typ(t, 'adele');
    expect(ZoekPaneelStuur.sluitOpenPaneel(), isTrue);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pump();
    expect(p.stuur.dicht, isTrue);
    expect(ZoekPaneelStuur.sluitOpenPaneel(), isFalse);
  });

  group('wat er vliegt', () {
    testWidgets('het woord vliegt naar het andere veld en meldt dat het er is', (t) async {
      var klaar = 0;
      late BuildContext c;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (x) {
        c = x;
        return const Scaffold();
      })));
      vliegWoord(c, woord: 'khalid', van: const Rect.fromLTWH(20, 60, 200, 40), naar: () => const Rect.fromLTWH(70, 120, 200, 40), klaar: () => klaar++);
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('khalid'), findsOneWidget);
      final begin = t.getTopLeft(find.text('khalid'));
      await t.pump(const Duration(milliseconds: 300));
      final later = t.getTopLeft(find.text('khalid'));
      expect(later.dy, greaterThan(begin.dy));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('khalid'), findsNothing);
      expect(klaar, 1);
    });

    testWidgets('geen doel: er vliegt niets, en het woord verschijnt toch', (t) async {
      var klaar = 0;
      late BuildContext c;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (x) {
        c = x;
        return const Scaffold();
      })));
      vliegWoord(c, woord: 'khalid', van: const Rect.fromLTWH(20, 60, 200, 40), naar: () => null, klaar: () => klaar++);
      await t.pump();
      expect(find.text('khalid'), findsNothing);
      expect(klaar, 1);
    });

    testWidgets('de foto vliegt naar de Hero op de pagina en verdwijnt daarna', (t) async {
      late BuildContext c;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (x) {
        c = x;
        return const Scaffold(body: Center(child: Hero(tag: 'doel', child: SizedBox(width: 200, height: 200))));
      })));
      vliegBeeld(c, van: const Rect.fromLTWH(10, 10, 40, 40), beeld: const ColoredBox(key: ValueKey('vlieger'), color: Colors.red), heroTag: 'doel', zoekIn: c);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('vlieger')), findsOneWidget);
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(find.byKey(const ValueKey('vlieger')), findsNothing);
      expect(t.takeException(), isNull);
    });
  });
}
