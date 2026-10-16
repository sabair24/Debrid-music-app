// De tv als leunstoel (Saber, 16-10-2026, vier rondes vragen): de selectie op een vaste plek, rijen
// die onthouden waar je stond, tabbladen die vanzelf wisselen na een halve tel, knoppen in glas met
// paarse letters zonder rand, en na twee minuten stilstand Nu speelt.
import 'dart:io';

import 'package:debridmusic/main.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/kleuren.dart';
import 'package:debridmusic/ui/tv_rij.dart';
import 'package:debridmusic/ui/vlak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Een rij van [n] tegels van 100 breed, elk met een eigen sleutel.
Widget _rij(String naam, {int n = 12, double marge = 24}) => SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: marge),
        itemCount: n,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => Pressable(
          key: ValueKey('$naam$i'),
          onPressed: () {},
          ringOnFocus: false,
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    );

FocusNode _knoop(WidgetTester t, String sleutel) =>
    Focus.of(t.element(find.descendant(of: find.byKey(ValueKey(sleutel)), matching: find.byType(GestureDetector)).first));

bool _heeft(WidgetTester t, String sleutel) => _knoop(t, sleutel).hasPrimaryFocus;

void main() {
  // Zoals op de tv: een afstandsbediening is een toetsenbord, dus de selectie is altijd zichtbaar. In
  // een toets staat Flutter anders op "aanraken" tot er een toets valt, en dan toont niets zijn focus.
  setUp(() {
    setTvModeForTest(true);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  });
  tearDown(() {
    setTvModeForTest(false);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  group('de selectie op een vaste plek', () {
    test('het doel: tegen de voorrand min de marge, binnen de grenzen van de lijst', () {
      expect(vastePlekDoel(onthul: 500, voorrand: 24, min: 0, max: 1000), 476);
      expect(vastePlekDoel(onthul: 10, voorrand: 24, min: 0, max: 1000), 0, reason: 'het begin schuift niet verder');
      expect(vastePlekDoel(onthul: 1200, voorrand: 24, min: 0, max: 1000), 1000, reason: 'het einde ook niet');
    });

    testWidgets('in een rij staat de gekozen hoes waar de eerste in rust staat', (t) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: Align(alignment: Alignment.topLeft, child: _rij('a')))));
      final rust = t.getTopLeft(find.byKey(const ValueKey('a0'))).dx;
      expect(rust, 24);
      _knoop(t, 'a5').requestFocus();
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.byKey(const ValueKey('a5'))).dx, closeTo(rust, 1),
          reason: 'in het midden dwaalde de selectie over het scherm');
    });

    testWidgets('in een staande lijst staat de selectie vast onder de bovenrand', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(children: [
            for (var i = 0; i < 30; i++)
              Pressable(key: ValueKey('r$i'), onPressed: () {}, child: const SizedBox(height: 60, width: 300)),
          ]),
        ),
      ));
      _knoop(t, 'r8').requestFocus();
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.byKey(const ValueKey('r8'))).dy, closeTo(kTvBovenruimte, 1));
      _knoop(t, 'r9').requestFocus();
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.byKey(const ValueKey('r9'))).dy, closeTo(kTvBovenruimte, 1),
          reason: 'de volgende rij komt op dezelfde plek: de lijst schuift, niet de selectie');
    });

    testWidgets('ook een InkWell-rij (Tracks) krijgt de vaste plek', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: 40,
            itemExtent: 76,
            itemBuilder: (_, i) => Builder(
              builder: (rij) => InkWell(
                key: ValueKey('i$i'),
                onTap: () {},
                onFocusChange: tvVolgFocus(rij),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ));
      Focus.of(t.element(find.descendant(of: find.byKey(const ValueKey('i5')), matching: find.byType(SizedBox)).first))
          .requestFocus();
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.byKey(const ValueKey('i5'))).dy, closeTo(kTvBovenruimte, 1),
          reason: 'hier stond de vierde rij half onder de spelerbalk');
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main, contains('                onFocusChange: tvVolgFocus(rij),'));
      expect(main, contains('const double kTvAlbumHoes = 180;'));
    });

    testWidgets('wie het uitzet (de bovenbalk), krijgt het midden', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ListView(children: [
              for (var i = 0; i < 30; i++)
                Pressable(
                    key: ValueKey('m$i'), onPressed: () {}, vastePlek: false, child: const SizedBox(height: 40, width: 300)),
            ]),
          ),
        ),
      ));
      _knoop(t, 'm8').requestFocus();
      await t.pumpAndSettle();
      expect(t.getCenter(find.byKey(const ValueKey('m8'))).dy, closeTo(200, 2));
    });
  });

  group('een rij onthoudt waar je stond', () {
    Widget scherm() => MaterialApp(
          home: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rechts van het midden, zoals "Bekijken" op de kaart van een nieuw album.
                Padding(
                  padding: const EdgeInsets.only(left: 300),
                  child: Pressable(key: const ValueKey('knop'), onPressed: () {}, child: const SizedBox(width: 120, height: 40)),
                ),
                TvRij(child: _rij('a')),
                TvRij(child: _rij('b')),
              ],
            ),
          ),
        );

    testWidgets('de eerste keer de eerste hoes, ook als er een andere dichterbij staat', (t) async {
      await t.pumpWidget(scherm());
      _knoop(t, 'knop').requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(_heeft(t, 'a0'), isTrue, reason: 'recht onder de knop staat de derde hoes');
    });

    testWidgets('terug in een rij: waar je was', (t) async {
      await t.pumpWidget(scherm());
      _knoop(t, 'a0').requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(_heeft(t, 'a2'), isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(_heeft(t, 'b0'), isTrue, reason: 'een rij waar je nog niet was: de eerste');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.pumpAndSettle();
      expect(_heeft(t, 'a2'), isTrue, reason: 'de rij erboven onthield de derde');
    });

    testWidgets('buiten een tv doet de rij niets', (t) async {
      setTvModeForTest(false);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: TvRij(child: _rij('a')))));
      expect(find.descendant(of: find.byType(TvRij), matching: find.byType(Focus)), findsWidgets);
      expect(t.widget<TvRij>(find.byType(TvRij)).child, isA<SizedBox>());
    });
  });

  group('de bovenbalk', () {
    Future<(List<int>, List<String>, TvBalkKnoppen)> balk(WidgetTester t) async {
      final gekozen = <int>[], anders = <String>[];
      final knoppen = TvBalkKnoppen();
      addTearDown(knoppen.dispose);
      final cfg = AppSettings();
      final d = DownloadManager(OnlineService(cfg), SoulseekService(cfg), Directory.systemTemp.path, () async {});
      t.view.physicalSize = const Size(1920, 400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ChangeNotifierProvider<DownloadManager>.value(
        value: d,
        child: MaterialApp(
          home: Scaffold(
            body: TvTopBar(
              view: 5,
              knoppen: knoppen,
              onPick: gekozen.add,
              onIn: () => anders.add('in'),
              onSearch: () => anders.add('zoeken'),
              onSettings: () {},
            ),
          ),
        ),
      ));
      return (gekozen, anders, knoppen);
    }

    testWidgets('blijf een halve tel op een tabblad, dan wisselt de pagina', (t) async {
      final (gekozen, _, knoppen) = await balk(t);
      knoppen.voor(0).requestFocus(); // Albums
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(gekozen, isEmpty, reason: 'nog geen halve tel');
      await t.pump(const Duration(milliseconds: 150));
      expect(gekozen, [0]);
    });

    testWidgets('snel voorbij schuiven laadt niets', (t) async {
      final (gekozen, _, knoppen) = await balk(t);
      knoppen.voor(0).requestFocus();
      await t.pump(const Duration(milliseconds: 200));
      knoppen.voor(4).requestFocus(); // Tracks
      await t.pump(const Duration(milliseconds: 200));
      knoppen.voor(1).requestFocus(); // Artiesten
      await t.pump(const Duration(milliseconds: 600));
      expect(gekozen, [1], reason: 'alleen waar je bleef staan');
    });

    testWidgets('het tabblad van de pagina waar je bent, wisselt niet', (t) async {
      final (gekozen, _, knoppen) = await balk(t);
      knoppen.voor(5).requestFocus(); // Start: daar ben je al
      await t.pump(const Duration(milliseconds: 700));
      expect(gekozen, isEmpty);
    });

    testWidgets('OK: wisselen en de pagina in', (t) async {
      final (gekozen, anders, knoppen) = await balk(t);
      knoppen.voor(4).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pump();
      expect(gekozen, [4]);
      expect(anders, ['in']);
      await t.pump(const Duration(milliseconds: 700));
      expect(gekozen, [4], reason: 'na OK niet nog eens vanzelf');
    });

    testWidgets('geselecteerd: glas met paarse letters; de pagina waar je bent: wit op grijs', (t) async {
      final (_, _, knoppen) = await balk(t);
      Color kleurVan(String label) => t.widget<Text>(find.text(label)).style!.color!;
      expect(kleurVan('Start'), Colors.white);
      knoppen.voor(0).requestFocus();
      await t.pump();
      expect(kleurVan('Albums'), kAccent);
      final pil = t.widget<AnimatedContainer>(
          find.ancestor(of: find.text('Albums'), matching: find.byType(AnimatedContainer)).first);
      final deco = pil.decoration! as BoxDecoration;
      expect(deco.gradient, kTvTabbladGlas, reason: 'glas, geen witte pil meer');
      expect(deco.color, isNull);
    });

    testWidgets('omhoog naar de balk landt op het tabblad van de pagina waar je bent', (t) async {
      // De regel zelf staat in de schil ([_landingsplek]); hier: de balk geeft dat tabblad terug.
      final (_, _, knoppen) = await balk(t);
      expect(knoppen.actief(5), isNotNull);
      expect(knoppen.actief(5)!.context, isNotNull, reason: 'aan de knop van Start gehangen');
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main, contains('    if (identical(scope, _tvBalk)) {\n      final actief = _tvKnoppen.actief(_view);'));
    });
  });

  group('knoppen: geen rand, paarse letters, glas', () {
    testWidgets('een glasknop krijgt paarse letters als hij de selectie heeft', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: GlasKnop(icoon: Icons.shuffle_rounded, label: 'Shuffle alles', onPressed: () {}))),
      ));
      Color? letters() => t.widget<FilledButton>(find.byWidgetPredicate((w) => w is FilledButton)).style!.foregroundColor!.resolve({});
      expect(letters(), Colors.white);
      Focus.of(t.element(find.text('Shuffle alles'))).requestFocus();
      await t.pump();
      expect(letters(), kAccent);
      expect(t.widget<Icon>(find.byIcon(Icons.shuffle_rounded)).color, kAccent);
    });

    test('een pictogramknop met een vaste kleur wordt paars bij selectie, alleen op een tv', () {
      final stijl = tvIcoonStijl(kGedempt);
      expect(stijl.foregroundColor!.resolve({WidgetState.focused}), kAccent);
      expect(stijl.foregroundColor!.resolve({}), kGedempt);
      setTvModeForTest(false);
      expect(stijl.foregroundColor!.resolve({WidgetState.focused}), kGedempt);
    });

    test('aangesloten: thema zonder rand op tv, paars gevuld wordt glas, spelerbalk paars', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main, contains('!isTv && states.contains(WidgetState.focused) ? BorderSide(color: kTvSelectie, width: 2) : null'));
      expect(main, contains('(states) => isTv && states.contains(WidgetState.focused) ? kAccent : null'));
      expect(main, contains('Color get _knopVulling => isTv ? kTvKnopGlas : _accent;'));
      expect('backgroundColor: _knopVulling'.allMatches(main).length, greaterThanOrEqualTo(30));
      expect(main, isNot(contains('backgroundColor: _accent,')), reason: 'geen paars gevulde knop meer op een tv');
      expect('style: tvIcoonStijl('.allMatches(main).length, greaterThanOrEqualTo(9));
      expect(main, contains("SizedBox(height: hoogteVanTegelrij(context), child: TvRij(child: row)),"));
    });
  });

  testWidgets('het onderschrift onder een pictogram duwt de buren niet opzij', (t) async {
    // Op de Shield sprong de afspeelknop 190 punten naar rechts als "10 seconden terug" de selectie
    // kreeg: het onderschrift maakte zijn kolom zo breed als de tekst.
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          TvLabelled(
            label: '10 seconden terug',
            child: IconButton(icon: const Icon(Icons.replay_10_rounded), onPressed: () {}),
          ),
          const SizedBox(key: ValueKey('buur'), width: 40, height: 40),
        ]),
      ),
    ));
    final voor = t.getTopLeft(find.byKey(const ValueKey('buur'))).dx;
    Focus.of(t.element(find.byIcon(Icons.replay_10_rounded))).requestFocus();
    await t.pump();
    expect(find.text('10 seconden terug'), findsOneWidget);
    expect(t.getTopLeft(find.byKey(const ValueKey('buur'))).dx, voor);
    expect(t.widget<Text>(find.text('10 seconden terug')).style!.color, kAccent);
  });

  test('vanuit de bovenbalk de pagina in: het eerste element links, niet wat onder het tabblad staat', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main, contains('        _landingsplek(scope, richting, vanwaar, links: uitBalk)?.requestFocus();'));
    expect(main, contains('          _landingsplek(scope, TraversalDirection.down, vanwaar, links: true)?.requestFocus();'));
    expect(main, contains('    if (links) {\n      rij.sort((a, b) => a.rect.left.compareTo(b.rect.left));'));
    // Een selectie op iets onzichtbaars telt als "nergens" (lege Favorieten, omhoog vanuit de
    // spelerbalk: daarna deed geen enkele pijl nog iets).
    expect(main, contains('&& _opScherm(hier!)) return false;'));
    expect('if (_heeftZichtbaar(scope)) {'.allMatches(main).length, 2);
  });

  group('na twee minuten stilstand: Nu speelt', () {
    test('alleen als er muziek speelt en er niets over de pagina ligt', () {
      expect(kTvStilstand, const Duration(minutes: 2));
      expect(naarNuSpeeltNaStilstand(stil: const Duration(minutes: 2), speelt: true, bovenaan: true), isTrue);
      expect(naarNuSpeeltNaStilstand(stil: const Duration(seconds: 119), speelt: true, bovenaan: true), isFalse);
      expect(naarNuSpeeltNaStilstand(stil: const Duration(minutes: 5), speelt: false, bovenaan: true), isFalse,
          reason: 'stil scherm zonder muziek: Android TV doet het zelf');
      expect(naarNuSpeeltNaStilstand(stil: const Duration(minutes: 5), speelt: true, bovenaan: false), isFalse,
          reason: 'een menu, een dialoog of Nu speelt zelf');
    });

    test('mediatoetsen doen gewoon hun werk; aangesloten op het vangnet', () {
      expect(kMediatoetsen, contains(LogicalKeyboardKey.mediaPlayPause));
      expect(kMediatoetsen, isNot(contains(LogicalKeyboardKey.select)));
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main, contains('    if (isTv && mounted && _tvStilWekker(e)) return true;'));
      expect(main, contains("_stilKlok = Timer.periodic(const Duration(seconds: 10), (_) => _kijkStilstand());"));
    });
  });

  test('kaarten groeien een beetje, met de schaduw van een hoes; tegeltitels twee regels', () {
    expect(kTvKaartGroei, inInclusiveRange(1.02, 1.05));
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main, contains('      focusScale: kTvKaartGroei,\n      ringOnFocus: false,'));
  });
}
