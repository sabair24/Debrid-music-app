/// De meetronde (Saber, 23-10-2026: "het is tijd om eens de performance te meten, begin eens op men mac" en "zorg er
/// dan voor, zo kan je het beste meten").
///
/// Wat hier vastligt:
/// - de cijfers per rij beelden: gemiddeld, p90 en maximum rasteren, bouwen, en hoeveel beelden te laat waren voor
///   een scherm van 120 Hz;
/// - alleen beelden die ná het eerste merkteken begonnen tellen;
/// - de opdracht `meet` over de zonelijn start de ronde, en zonder ronde zegt het toestel dat het niet kan;
/// - een ronde: begin, één melding per variant, het glas per variant en terug, de schakelaars weer uit, en "klaar";
/// - de kantelhoes geeft de grootste hoes voor de muis, en staat stil in een variant zonder kantelen.
library;

import 'dart:io';

import 'package:debridmusic/main.dart' show FotoTijdensSchuiven;
import 'package:debridmusic/meetronde.dart';
import 'package:debridmusic/ui/glas.dart' show GlasKwaliteit, GlasStand, glasMat;
import 'package:debridmusic/player.dart' show Rijbediening, Speelbron;
import 'package:debridmusic/ui/kantel_hoes.dart';
import 'package:debridmusic/zone_opdracht.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('de cijfers', () {
    test('gemiddeld, p90, maximum, en te laat op 120 Hz (8,3 ms)', () {
      final c = Beeldcijfers.uit([1000, 2000, 12000], [5000, 9000, 3000], hz: 120);
      expect(c.aantal, 3);
      expect(c.rasterGemMs, closeTo(5.67, .01));
      expect(c.rasterP90Ms, 9.0);
      expect(c.rasterMaxMs, 9.0);
      expect(c.bouwMaxMs, 12.0);
      expect(c.teLaat, 2, reason: 'eentje te traag gerasterd, eentje te traag gebouwd');
      expect(c.budgetMs, closeTo(8.33, .01));
      expect(c.regel('kantel', ['glas', 'spiegel']),
          '[meet] kantel | zonder glas+spiegel | 3 beelden | rasteren gem 5.7 · p90 9.0 · max 9.0 ms | '
          'bouwen gem 5.0 · max 12.0 ms | te laat 2 (>8.3 ms)');
      expect(Beeldcijfers.uit(const [], const [], hz: 120).regel('stil', const []), contains('alles aan | 0 beelden'));
    });

    test('alleen wat ná het merkteken begon', () {
      expect(binnen(100, 100, 200), isFalse, reason: 'het beeld van het merkteken zelf');
      expect(binnen(101, 100, 200), isTrue);
      expect(binnen(200, 100, 200), isTrue);
      expect(binnen(201, 100, 200), isFalse);
    });
  });

  group('op afstand', () {
    test('de opdracht "meet" start de ronde; zonder ronde zegt het toestel dat het niet kan', () async {
      final s = _NepSpeler();
      final gevraagd = <Map<String, dynamic>>[];
      final u = ZoneUitvoerder(speler: s, rij: s, nummer: (_) => null, meet: (op) async => gevraagd.add(op));
      expect(await u.voerUit({'id': '1', 'cmd': 'meet', 'scenarios': ['open']}), isNull);
      expect(gevraagd.single['scenarios'], ['open']);
      final zonder = ZoneUitvoerder(speler: s, rij: s, nummer: (_) => null);
      expect(await zonder.voerUit({'id': '2', 'cmd': 'meet'}), isNotNull);
    });

    test('een ronde: begin, per variant een melding, het glas per variant en terug, en klaar', () async {
      final gemeld = <String>[];
      final glas = <String>[];
      var bereid = 0, klaar = 0;
      Set<String>? tijdens;
      await voerMeetrondeUit({
        'scenarios': <String>[],
        'varianten': [
          <String>[],
          ['glas'],
          ['glasmat', 'spiegel'],
          ['bestaat-niet'],
        ],
      }, MeetHaken(
        openNuSpeelt: () {},
        sluitNuSpeelt: () {},
        meld: (r) async {
          gemeld.addAll(r);
          tijdens ??= meetZonder.value.contains('spiegel') ? {...meetZonder.value} : null;
        },
        zetGlas: (stand, {klaar = false}) => glas.add('${stand ?? '-'}${klaar ? ' klaar' : ''}'),
        bereid: ({required spelen}) async {
          bereid++;
          return 'klaargezet';
        },
        klaar: () async => klaar++,
      ), hz: 120);
      expect(gemeld.first, startsWith('[meet] begin:'));
      expect(gemeld.first, contains('4 varianten, 120 Hz — klaargezet'));
      expect(gemeld.last, '[meet] klaar');
      expect(glas, ['-', 'plat', 'mat', '-', '- klaar'],
          reason: 'per variant de stand, een onbekend effect telt niet, en op het einde terug');
      expect(tijdens, {'glasmat', 'spiegel'}, reason: 'de effecten staan uit terwijl die variant meet');
      expect(meetZonder.value, isEmpty, reason: 'na de ronde staat alles weer aan');
      expect(bereid, 1);
      expect(klaar, 1);
      expect(meetrondeLoopt, isFalse);
    });
  });

  group('Nu speelt als foto', () {
    testWidgets('bij het sluiten een foto, bij het openen levend; de meetronde kan beide omzetten', (t) async {
      final c = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 300));
      addTearDown(c.dispose);
      Future<bool> foto({bool open = false, bool dicht = true}) async {
        await t.pumpWidget(MaterialApp(
            home: FotoTijdensSchuiven(animatie: c, open: open, dicht: dicht, child: const ColoredBox(color: Colors.red))));
        return t.widget<SnapshotWidget>(find.byType(SnapshotWidget)).controller.allowSnapshotting;
      }

      c.forward();
      await t.pump();
      expect(await foto(), isFalse, reason: 'openen: levend (de vervaagde achtergrond komt pas later)');
      expect(await foto(open: true), isTrue, reason: 'meetronde "foto"');
      c.value = 1;
      c.reverse();
      await t.pump();
      expect(await foto(), isTrue, reason: 'sluiten: één foto (Mac: piekbeelden van 156 naar 17 ms)');
      expect(await foto(dicht: false), isFalse, reason: 'meetronde "levend"');
      await t.pump(const Duration(seconds: 1));
      expect(await foto(), isFalse, reason: 'stil: het echte scherm');
    });
  });

  testWidgets('openen als foto: pas na drie beelden, en opnieuw zodra de achtergrond klaar is', (t) async {
    final c = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 320));
    addTearDown(c.dispose);
    final klaar = ValueNotifier<int>(0);
    addTearDown(klaar.dispose);
    await t.pumpWidget(MaterialApp(
        home: FotoTijdensSchuiven(
            animatie: c, open: true, openNaBeelden: 3, herFotoBij: klaar, child: const ColoredBox(color: Colors.red))));
    SnapshotController foto() => t.widget<SnapshotWidget>(find.byType(SnapshotWidget)).controller;
    c.forward();
    await t.pump(const Duration(milliseconds: 8));
    expect(foto().allowSnapshotting, isFalse, reason: 'het eerste beeld levend');
    await t.pump(const Duration(milliseconds: 8));
    await t.pump(const Duration(milliseconds: 8));
    await t.pump(const Duration(milliseconds: 8));
    expect(foto().allowSnapshotting, isTrue, reason: 'daarna een foto');
    var opnieuw = 0;
    foto().addListener(() => opnieuw++);
    klaar.value++;
    expect(opnieuw, greaterThan(0), reason: 'de achtergrond kwam later: een nieuwe foto');
    await t.pump(const Duration(milliseconds: 400));
    expect(foto().allowSnapshotting, isFalse, reason: 'open: het echte scherm');
  });

  testWidgets('op de pc: het glas zonder vervaging zolang Nu speelt schuift, daarna weer zoals het was', (t) async {
    // Saber, 23-10-2026, gekozen: "Vervaging uit tijdens schuiven" (pc: Nu speelt openen 61 → 6 te late beelden).
    final c = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 300));
    addTearDown(c.dispose);
    final voor = GlasKwaliteit.stand.value;
    GlasKwaliteit.stand.value = GlasStand.mat;
    addTearDown(() => GlasKwaliteit.stand.value = voor);
    await t.pumpWidget(MaterialApp(
        home: FotoTijdensSchuiven(animatie: c, glasPlat: true, child: const ColoredBox(color: Colors.red))));
    c.forward();
    await t.pump();
    expect(GlasKwaliteit.stand.value, GlasStand.plat, reason: 'hier (een pc) plat tijdens het schuiven');
    await t.pump(const Duration(milliseconds: 400));
    expect(GlasKwaliteit.stand.value, GlasStand.mat, reason: 'en weer mat als het stilstaat');
    c.reverse();
    await t.pump();
    expect(GlasKwaliteit.stand.value, GlasStand.plat);
    await t.pump(const Duration(milliseconds: 400));
    expect(GlasKwaliteit.stand.value, GlasStand.mat);
    // Een meetronde met "schuifglas": zoals vroeger.
    meetZonder.value = {'schuifglas'};
    c.forward();
    await t.pump();
    expect(GlasKwaliteit.stand.value, GlasStand.mat);
    meetZonder.value = const {};
    await t.pump(const Duration(milliseconds: 400));
    // Weg tijdens het schuiven: het glas komt terug.
    c.reverse();
    await t.pump();
    expect(GlasKwaliteit.stand.value, GlasStand.plat);
    await t.pumpWidget(const SizedBox());
    expect(GlasKwaliteit.stand.value, GlasStand.mat, reason: 'weg midden in het schuiven: het glas komt terug');
    c.stop();
  });

  test('een andere hoofdpagina wisselt als foto (gsm: 13 van 21 beelden te laat bij Favorieten, zonder overgang 1)', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final wissel = main.substring(main.indexOf('          AnimatedSwitcher(\n              // Een meetronde met `overgang`'));
    expect(wissel.substring(0, 1800), contains("child: FotoTijdensSchuiven(\n                      animatie: animatie,\n"
        "                      open: !zonderVoorMeting('paginalevend'),\n"
        "                      dicht: !zonderVoorMeting('paginalevend'),"));
  });

  test('het matglas: buiten een meetronde altijd hetzelfde filter (de BackdropGroup voegt alleen gelijke samen)', () {
    expect(identical(glasMat, glasMat), isTrue);
    meetZonder.value = {'dilate'};
    final ander = glasMat;
    meetZonder.value = const {};
    expect(identical(ander, glasMat), isFalse, reason: 'een variant heeft zijn eigen filter');
    expect(identical(glasMat, glasMat), isTrue);
  });

  group('wat een blok kost (MeetBlok)', () {
    tearDown(() => meetrondeLooptVoorToets = false);

    testWidgets('DE KERN: tijdens een meetronde telt hij bouwen, opmaak en tekenen, en de regel zet weer op nul',
        (t) async {
      meetrondeLooptVoorToets = true;
      blokkenRegel();
      await t.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: MeetBlok('raster', child: Column(children: [MeetBlok('tegel', child: Text('a')), MeetBlok('tegel', child: Text('b'))])),
      ));
      final regel = blokkenRegel();
      expect(regel, contains('raster 1× bouwen'));
      expect(regel, contains('tegel 2× bouwen'));
      expect(regel, contains('opmaak'));
      expect(regel, contains('tekenen'));
      expect(blokkenRegel(), isEmpty, reason: 'na het lezen weer op nul');
    });

    testWidgets('DE GRENS: zonder meetronde telt hij niets', (t) async {
      meetrondeLooptVoorToets = false;
      await t.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: MeetBlok('raster', child: Text('a'))));
      expect(blokkenRegel(), isEmpty);
      meetTel('sorteren', bouwen: 100);
      expect(blokkenRegel(), isEmpty);
    });

    test('de bedrading: Albums, de rij, de tegel, de pagina en de sortering; geen stilstand tijdens een meetronde', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main, contains("return MeetBlok('Albums',"));
      expect(main, contains("return MeetBlok('Albumrij', child: SizedBox("));
      expect(main, contains("return MeetBlok('Albumtegel', child: AlbumTegel("));
      expect(main, contains("child: KeyedSubtree(key: ValueKey(_view), child: MeetBlok('pagina', child: _content())),"));
      expect(main, contains("meetTel('sorteren', bouwen: sw.elapsedMicroseconds);"));
      final begin = main.indexOf('void _kijkStilstand()');
      final lijf = main.substring(begin, main.indexOf('\n  }\n', begin));
      expect(lijf, contains('if (meetrondeLoopt) {'));
      final ronde = File('lib/meetronde.dart').readAsStringSync();
      expect(ronde, contains(r"uit.add(('$naam openen', open, blokkenRegel()));"));
    });
  });

  group('de lijst in het midden (scenario "paginas")', () {
    testWidgets('de verticale lijst die je ziet, niet de rij ernaast; zonder lijst niets', (t) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final verticaal = ScrollController();
      addTearDown(verticaal.dispose);
      await t.pumpWidget(MaterialApp(
        home: ListView(controller: verticaal, children: [
          for (var i = 0; i < 6; i++) const SizedBox(height: 300),
          // Midden in beeld een horizontale rij (zoals op Start): die telt niet.
          SizedBox(
            height: 200,
            child: ListView(scrollDirection: Axis.horizontal, children: [for (var i = 0; i < 9; i++) const SizedBox(width: 300)]),
          ),
          for (var i = 0; i < 6; i++) const SizedBox(height: 300),
        ]),
      ));
      verticaal.jumpTo(1700);
      await t.pump();
      expect(lijstInHetMidden(), same(verticaal.position));
      await t.pumpWidget(const MaterialApp(home: SizedBox.expand()));
      expect(lijstInHetMidden(), isNull);
    });

    test('alleen bij "alles aan", en standaard niet', () {
      expect(kMeetScenarios.keys, contains('paginas'));
      expect(kMeetStandaard, isNot(contains('paginas')), reason: 'duurt ruim een minuut: alleen als je erom vraagt');
    });
  });

  group('de kantelhoes', () {
    testWidgets('de grootste hoes voor de muis; zonder kantelen geen muis en geen draai', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Column(children: [
          SizedBox(width: 80, height: 80, child: KantelHoes(child: ColoredBox(color: Colors.red))),
          SizedBox(width: 300, height: 300, child: KantelHoes(child: ColoredBox(color: Colors.blue))),
        ]),
      ));
      expect(KantelHoes.grootsteVak()?.size, const Size(300, 300));
      expect(find.descendant(of: find.byType(KantelHoes), matching: find.byType(MouseRegion)), findsWidgets);
      meetZonder.value = {'kantel'};
      addTearDown(() => meetZonder.value = const {});
      await t.pumpWidget(const MaterialApp(home: KantelHoes(child: ColoredBox(color: Colors.red))));
      expect(find.descendant(of: find.byType(KantelHoes), matching: find.byType(MouseRegion)), findsNothing);
      expect(find.descendant(of: find.byType(KantelHoes), matching: find.byType(Transform)), findsNothing);
    });
  });
}

class _NepSpeler implements Speelbron, Rijbediening {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

