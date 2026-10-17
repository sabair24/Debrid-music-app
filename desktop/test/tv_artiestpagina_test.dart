// De artiestpagina op een tv (Saber, 16-10-2026, vier rondes vragen): de foto loopt onder het zwevende
// menu door tot de bovenrand, de naam is half zo groot, "In mijn bibliotheek" heeft het paneel van de
// pc waar de cd uit de hoes schuift, en een gekozen link is wit en onderstreept, zonder vak.
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/navigatie.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/kleuren.dart';
import 'package:debridmusic/ui/typografie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Een geldige PNG van één doorzichtige pixel: genoeg voor een hoes, en daarmee een schijf ernaast.
final _pixel = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
  0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
  0x0D, 0x0A, 0x2D, 0xB4,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

const _titels = ['Bad', 'Thriller', 'Off The Wall', 'Dangerous', 'Ben', 'Got To Be There', 'Invincible',
  'Xscape', 'Michael', 'Scream'];

List<Album> _albums(int n) => [
      for (var i = 0; i < n; i++)
        Album(_titels[i], 'Michael Jackson', [
          for (var j = 0; j < 3; j++)
            Track(path: 'x/${_titels[i]}/$j.flac', title: 'n$j', artist: 'Michael Jackson', album: _titels[i], year: 2000 - i),
        ])
          ..embeddedCover = _pixel,
    ];

/// Zoals op de Shield: 960 bij 540 punten.
Future<void> _scherm(WidgetTester t) async {
  t.view.physicalSize = const Size(960, 540);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget _omhulsel(Widget kind) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
        ChangeNotifierProvider<AppSettings>(create: (_) => AppSettings()),
      ],
      child: MaterialApp(home: Scaffold(body: kind)),
    );

FocusNode _knoopVan(WidgetTester t, Finder f) => Focus.of(t.element(f));

Finder _titel(String t) => find.text(t.toUpperCase()).first;

Pressable _regel(WidgetTester t, String titel) =>
    t.widget<Pressable>(find.ancestor(of: _titel(titel), matching: find.byType(Pressable)).first);

void main() {
  setUpAll(() => setAppDirForTest(Directory.systemTemp.createTempSync('tv_artiestpagina').path));
  setUp(() {
    setTvModeForTest(true);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  });
  tearDown(() {
    setTvModeForTest(false);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  group('de selectie onder het zwevende menu', () {
    testWidgets('een pagina die onder het menu door tekent: de vaste plek ligt onder de capsule, niet erachter',
        (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BalkRuimte(
            hoogte: 75,
            child: ListView(children: [
              for (var i = 0; i < 30; i++)
                Pressable(key: ValueKey('r$i'), onPressed: () {}, child: const SizedBox(height: 60, width: 300)),
            ]),
          ),
        ),
      ));
      _knoopVan(t, find.descendant(of: find.byKey(const ValueKey('r8')), matching: find.byType(GestureDetector)).first)
          .requestFocus();
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.byKey(const ValueKey('r8'))).dy, closeTo(75 + kTvBovenruimte, 1),
          reason: 'de lijst begint bovenaan het venster; op 56 stond de selectie achter de capsule');
    });

    testWidgets('een lijst ín de pagina rekent het menu niet mee, de pagina zelf wel', (t) async {
      final pagina = ScrollController();
      addTearDown(pagina.dispose);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BalkRuimte(
            hoogte: 75,
            child: ListView(controller: pagina, children: [
              const SizedBox(height: 700),
              SizedBox(
                key: const ValueKey('binnen'),
                height: 200,
                child: ListView(children: [
                  for (var i = 0; i < 10; i++)
                    Pressable(key: ValueKey('b$i'), onPressed: () {}, child: const SizedBox(height: 60, width: 300)),
                ]),
              ),
              const SizedBox(height: 900),
            ]),
          ),
        ),
      ));
      // Eerst de lijst in beeld, anders is hij nog niet gebouwd.
      pagina.jumpTo(500);
      await t.pump();
      _knoopVan(t, find.descendant(of: find.byKey(const ValueKey('b5'), skipOffstage: false), matching: find.byType(SizedBox, skipOffstage: false), skipOffstage: false).last)
          .requestFocus();
      await t.pumpAndSettle();
      final binnen = t.getTopLeft(find.byKey(const ValueKey('binnen'))).dy;
      expect(binnen, closeTo(75 + kTvBovenruimte, 1), reason: 'de pagina zet de lijst onder de capsule');
      expect(t.getTopLeft(find.byKey(const ValueKey('b5'))).dy - binnen, closeTo(kTvBovenruimte, 1),
          reason: 'binnen de lijst telt het menu niet: die schuift mee met de pagina');
    });
  });

  group('een pijl kiest niets dat nog geen plek op de pagina heeft', () {
    // Gemeten op de Shield (17-10-2026): knoppen in een sliver ver onder het beeld stonden voor de
    // pijl op de onderrand van het beeld, en "Toon alle 29" won zo van de eerste plaat eronder.
    // Alleen Flutter 3.41 (de bouwstraat) zet zo'n knop op de onderrand; 3.35 (lokaal) geeft hem zijn
    // ware plek. De tweede toets vangt de fout dus pas in de bouwstraat — de eerste ook hier.
    Future<({FocusNode radio, FocusNode dichtbij, FocusNode ver})> pagina(WidgetTester t) async {
      t.view.physicalSize = const Size(960, 436);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final k = (radio: FocusNode(), dichtbij: FocusNode(), ver: FocusNode());
      addTearDown(() {
        k.radio.dispose();
        k.dichtbij.dispose();
        k.ver.dispose();
      });
      Widget knop(FocusNode n, double b, double h) =>
          Pressable(focusNode: n, onPressed: () {}, child: SizedBox(width: b, height: h));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomScrollView(slivers: [
            SliverToBoxAdapter(
                child: SizedBox(height: 400, child: Align(alignment: Alignment.bottomLeft, child: knop(k.radio, 110, 40)))),
            // Net onder het beeld, binnen het voorraadstuk: echt opgemaakt, met zijn ware plek.
            SliverToBoxAdapter(
                child: SizedBox(height: 120, child: Align(alignment: Alignment.bottomLeft, child: knop(k.dichtbij, 240, 40)))),
            const SliverToBoxAdapter(child: SizedBox(height: 3000)),
            // Ver weg: gebouwd (een SliverToBoxAdapter bouwt altijd), maar niet opgemaakt.
            SliverToBoxAdapter(child: Align(alignment: Alignment.centerLeft, child: knop(k.ver, 100, 24))),
          ]),
        ),
      ));
      k.radio.requestFocus();
      await t.pumpAndSettle();
      return k;
    }

    testWidgets('wat ver buiten beeld staat, telt niet als opgemaakt; wat net buiten beeld staat wel', (t) async {
      final k = await pagina(t);
      expect(nietOpgemaakt(k.ver), isTrue);
      expect(nietOpgemaakt(k.dichtbij), isFalse);
      expect(nietOpgemaakt(k.radio), isFalse);
    });

    testWidgets('omlaag gaat naar de knop vlak eronder, niet naar die van ver weg', (t) async {
      final k = await pagina(t);
      expect(tvPijlStap(k.radio, TraversalDirection.down), isTrue);
      await t.pumpAndSettle();
      expect(k.dichtbij.hasPrimaryFocus, isTrue,
          reason: 'zo sprong omlaag vanaf Radio naar "Toon alle 29" in plaats van naar de lijst');
      expect(k.ver.skipTraversal, isFalse, reason: 'na de stap hoort alles weer mee te tellen');
    });
  });

  group('In mijn bibliotheek (Saber: "net zoals pc, mac")', () {
    Future<void> bouw(WidgetTester t, int n) async {
      await _scherm(t);
      await t.pumpWidget(_omhulsel(SingleChildScrollView(
        child: Column(children: [
          FilledButton(key: const ValueKey('radio'), onPressed: () {}, child: const Text('Radio')),
          GetrapteLijst(albums: _albums(n)),
        ]),
      )));
      await t.pump();
    }

    AlbumArt paneel(WidgetTester t) => t.widget<AlbumArt>(find.byType(AlbumArt));

    testWidgets('het paneel staat er, en de cd schuift uit bij elke selectie', (t) async {
      await bouw(t, 3);
      expect(find.byType(AlbumArt), findsOneWidget, reason: 'op een tv stond er geen paneel, alleen duimnagels');
      expect(paneel(t).uitgeschoven, isFalse);
      _knoopVan(t, _titel('Thriller')).requestFocus();
      await t.pump();
      await t.pump();
      expect(paneel(t).album, 'Thriller');
      expect(paneel(t).uitgeschoven, isTrue, reason: 'de selectie is op een tv wat op de pc het aanwijzen is');
      _knoopVan(t, _titel('Off The Wall')).requestFocus();
      await t.pump();
      await t.pump();
      expect(paneel(t).album, 'Off The Wall');
      expect(paneel(t).uitgeschoven, isTrue);
      await t.pumpAndSettle();
    });

    testWidgets('de selectie de lijst uit: de cd terug in de hoes, en geen gekozen titel meer', (t) async {
      await bouw(t, 3);
      _knoopVan(t, _titel('Thriller')).requestFocus();
      await t.pump();
      await t.pump();
      _knoopVan(t, find.text('Radio')).requestFocus();
      await t.pump();
      await t.pump();
      expect(paneel(t).uitgeschoven, isFalse);
      expect(t.widget<Text>(_titel('Thriller')).style?.decoration, isNot(TextDecoration.underline),
          reason: 'een onderstreepte titel zegt dat de selectie daar staat, en hij stond op Radio');
      await t.pumpAndSettle();
    });

    testWidgets('gekozen = witte titel met een lijn eronder, zonder glas en zonder te groeien', (t) async {
      await bouw(t, 3);
      _knoopVan(t, _titel('Thriller')).requestFocus();
      await t.pump();
      await t.pump();
      final gekozen = t.widget<Text>(_titel('Thriller')).style!;
      expect(gekozen.decoration, TextDecoration.underline);
      expect(gekozen.color, kTekst);
      final ander = t.widget<Text>(_titel('Bad')).style!;
      expect(ander.decoration, isNot(TextDecoration.underline));
      expect(ander.color, kGedempt);
      final p = _regel(t, 'Thriller');
      expect(p.ringOnFocus, isFalse, reason: 'het grijze glas, met "01" erbuiten, vond Saber niet goed');
      expect(p.scaleOnFocus, isFalse, reason: 'een groeiende regel schoof met zijn nummer de marge in');
      expect(p.onLongPress, isNotNull, reason: 'lang OK: hetzelfde menu als een hoes elders');
      await t.pumpAndSettle();
    });

    testWidgets('getrapt zoals op de pc, zonder duimnagel', (t) async {
      await bouw(t, 3);
      final een = t.getTopLeft(find.text('01')).dx;
      final twee = t.getTopLeft(find.text('02')).dx;
      expect(twee - een, closeTo(72, .5), reason: 'het ritme van de pc: 0 / 72 / 24 …');
      // Alleen de hoes in het paneel: geen kleine hoesjes van 44 voor de titels.
      expect(find.byWidgetPredicate((w) => w is SizedBox && w.width == 44 && w.height == 44), findsNothing);
    });

    /// Zoals op de artiestpagina: een kop erboven, de pagina onder het zwevende menu door, en de lijst
    /// in diezelfde pagina.
    Future<void> pagina(WidgetTester t, int n) async {
      await _scherm(t);
      await t.pumpWidget(_omhulsel(BalkRuimte(
        hoogte: 75,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 400,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: FilledButton(onPressed: () {}, child: const Text('Radio')),
              ),
            ),
          ),
          SliverToBoxAdapter(child: GetrapteLijst(albums: _albums(n))),
          SliverToBoxAdapter(child: FilledButton(onPressed: () {}, child: const Text('Toon alles'))),
          const SliverToBoxAdapter(child: SizedBox(height: 900)),
        ]),
      )));
      await t.pump();
    }

    testWidgets('omlaag vanaf de knop erboven komt in de lijst, en daarna eruit', (t) async {
      // Op de Shield (17-10-2026) sprong omlaag vanaf Radio over de lijst heen: hij had een eigen
      // schuiflijst, en sinds Flutter 3.41 blijft omlaag in dezelfde schuiflijst zolang daar iets is.
      await pagina(t, 2);
      _knoopVan(t, find.text('Radio')).requestFocus();
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(paneel(t).album, 'Bad', reason: 'de selectie hoort op de eerste plaat van de lijst');
      expect(t.widget<Text>(_titel('Bad')).style?.decoration, TextDecoration.underline);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(paneel(t).album, 'Thriller');
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, _knoopVan(t, find.text('Toon alles')),
          reason: 'na de laatste plaat gaat omlaag gewoon verder de pagina af');
      expect(paneel(t).uitgeschoven, isFalse);
    });

    testWidgets('op een tv geen eigen schuiflijst in de lijst', (t) async {
      await bouw(t, 10);
      expect(find.descendant(of: find.byType(GetrapteLijst), matching: find.byType(Scrollable)), findsNothing,
          reason: 'een schuiflijst in de pagina is sinds Flutter 3.41 met de pijlen niet meer in te komen');
    });

    testWidgets('de lijst schuift met de pagina mee, en de hoes blijft op zijn plek', (t) async {
      await pagina(t, 10);
      final hoes = find.byType(AlbumArt);
      final plek = 75 + kTvBovenruimte;
      for (final titel in ['Bad', 'Off The Wall', 'Ben', 'Michael', 'Scream']) {
        _knoopVan(t, _titel(titel)).requestFocus();
        await t.pumpAndSettle();
        expect(t.getTopLeft(hoes).dy, closeTo(plek, 1.5),
            reason: 'Saber: "hoes blijft staan, lijst schuift" — en bij $titel stond hij ergens anders');
        final regel = t.getRect(_titel(titel));
        expect(regel.top, greaterThanOrEqualTo(plek - 1), reason: '$titel staat achter de balk');
        expect(regel.bottom, lessThan(540), reason: '$titel staat onder het scherm');
      }
    });

    testWidgets('buiten een tv: de regels groeien zoals voorheen, en het paneel kleeft niet', (t) async {
      setTvModeForTest(false);
      await bouw(t, 3);
      expect(_regel(t, 'Bad').scaleOnFocus, isTrue);
      expect(_regel(t, 'Bad').onLongPress, isNull);
      expect(find.descendant(of: find.byType(GetrapteLijst), matching: find.byType(ValueListenableBuilder<double>)),
          findsNothing);
    });
  });

  group('de kop', () {
    testWidgets('de naam is op een tv de maat uit de ontwerpschets, niet die van een iPad', (t) async {
      await _scherm(t);
      await t.pumpWidget(_omhulsel(const EditorialeKop(naam: 'Michael Jackson')));
      expect(t.widget<Text>(find.text('MICHAEL')).style?.fontSize, kTvArtiestNaam);
      setTvModeForTest(false);
      await t.pumpWidget(_omhulsel(const EditorialeKop(naam: 'Michael Jackson', key: ValueKey('pc'))));
      expect(t.widget<Text>(find.text('MICHAEL')).style?.fontSize, artiestNaamGrootte(960),
          reason: 'buiten een tv verandert er niets');
    });

    testWidgets('met de balk erboven loopt de foto tot de bovenrand, en de naam staat er net zo ver onder', (t) async {
      await _scherm(t);
      Future<double> naam(double bloed) async {
        await t.pumpWidget(_omhulsel(Align(
            alignment: Alignment.topLeft, child: EditorialeKop(naam: '*NSYNC', key: ValueKey(bloed), bovenBloed: bloed))));
        return t.getTopLeft(find.text('*NSYNC')).dy;
      }

      final zonder = await naam(0);
      final met = await naam(75);
      expect(met - zonder, closeTo(75, .5));
      expect(t.getSize(find.byType(EditorialeKop)).height, greaterThanOrEqualTo(kTvKopZicht + 75));
    });
  });

  testWidgets('VOLLEDIGE DISCOGRAFIE past op een tv op één regel, naast de telling en de sorteerpil', (t) async {
    // Met het echte lettertype: in een toets is elke letter anders een vierkantje van één em breed.
    await t.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
        inter.addFont(Future.value(ByteData.sublistView(File('fonts/Inter-$w.ttf').readAsBytesSync())));
      }
      await inter.load();
    });
    double breed(String s, TextStyle stijl) => (TextPainter(
          text: TextSpan(text: s, style: stijl.copyWith(fontFamily: 'Inter')),
          textDirection: TextDirection.ltr,
          textScaler: const TextScaler.linear(1.35),
        )..layout())
            .width;
    final kop = breed('VOLLEDIGE DISCOGRAFIE', kDisplayKlein.copyWith(fontSize: 20));
    final telling = breed('53 in 7 blokken', kOpschrift);
    // 960 min de tv-marge (2 × 48), de marge van de kop (2 × 28), de marge achter de pil (28) en de pil
    // zelf: 231 punten breed, gemeten op de Shield (16-10-2026).
    expect(kop + 12 + telling, lessThan(960 - 96 - 56 - 28 - 231),
        reason: 'op 30 brak hij in twee regels, en op één regel zou hij afgekapt worden');
  });

  group('tekstlinks', () {
    Future<void> link(WidgetTester t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            FilledButton(onPressed: () {}, child: const Text('ander')),
            TekstLink(
              onPressed: () {},
              bouw: (g) => Text('JC Chasez', style: tvLinkStijl(const TextStyle(color: kGedempt), g)),
            ),
          ]),
        ),
      ));
    }

    testWidgets('op een tv: gekozen = wit en onderstreept, zonder vak', (t) async {
      await link(t);
      expect(t.widget<Text>(find.text('JC Chasez')).style?.decoration, isNot(TextDecoration.underline));
      _knoopVan(t, find.text('JC Chasez')).requestFocus();
      await t.pump();
      await t.pump();
      final s = t.widget<Text>(find.text('JC Chasez')).style!;
      expect(s.decoration, TextDecoration.underline);
      expect(s.color, kTekst);
      expect(t.widget<Pressable>(find.byType(Pressable)).ringOnFocus, isFalse,
          reason: 'het grijze vak stond soms scheef over de letters');
    });

    testWidgets('buiten een tv: de ring zoals altijd, en de letters veranderen niet', (t) async {
      setTvModeForTest(false);
      await link(t);
      _knoopVan(t, find.text('JC Chasez')).requestFocus();
      await t.pump();
      await t.pump();
      expect(t.widget<Text>(find.text('JC Chasez')).style?.decoration, isNot(TextDecoration.underline));
      expect(t.widget<Pressable>(find.byType(Pressable)).ringOnFocus, isTrue);
    });
  });

  group('bedrading (gelezen uit lib/main.dart)', () {
    final bron = File('lib/main.dart').readAsStringSync();

    test('de tv-balk zweeft, met de melding mee in de zwevende laag', () {
      expect(bron, contains('if (isTv) Positioned(top: 0, left: 0, right: 0, child: _tvBovenlaag()),'));
      expect(bron, contains('(isTv ? TvTopBar.hoogte + tvOverscan.top + _tvMeldingHoogte : 0.0)'));
      expect(bron, contains('_MeetHoogte(\n            onHoogte: _zetTvMeldingHoogte,'));
    });

    test('de artiestpagina laat de tv-marge bovenaan weg zodra de balk zweeft', () {
      expect(bron, contains('minimum: EdgeInsets.only(top: ruimte > 0 ? 0 : tvOverscan.top),'));
    });

    // Shield, 17-10-2026: na het openen van een artiest had niets de selectie; op de albumpagina
    // stond de selectie op een uitklaprij zonder zichtbaar teken; en de beschrijving vergrootte bij
    // selectie over de schermrand.
    // Meetbouw b11980/b11981 (Shield, 17-10-2026): twintig keer bouwen bij het openen kostte 1,3 s,
    // vooral door bij elke herbouw van alle albums artistKey uit te rekenen; daarna 100 ms, waarvan
    // 90 voor het steeds opnieuw samenstellen van de discografie.
    test('de pagina rekent bij een herbouw niet alles opnieuw uit', () {
      expect(bron, contains('final eigenSleutel = artistKey(widget.artist.name);'));
      expect(bron, contains('.where((a) => artistKey(a.artist) == eigenSleutel)'));
      expect(bron, contains('final disco = _discografie(bezit);'));
      expect('vulHoezenAan(mergeDiscography([_dz, _mb, _dg]), {..._hoezen, ..._groepHoezen})'.allMatches(bron).length, 1);
      expect(bron, contains('if (vorige != null && _zelfdeInvoer(invoer, _discoInvoer)) return vorige;'));
    });

    test('bij openen staat de selectie op Radio', () {
      expect(bron, contains('autofocus: isTv,\n                      onPressed: () => startRadio(context, widget.artist.name),'));
    });

    test('"Op andere uitgaves" laat zien dat hij de selectie heeft', () {
      final i = bron.indexOf("Text('Op andere uitgaves");
      final rij = bron.substring(i - 900, i);
      expect(rij, contains('Pressable('));
      expect(rij, isNot(contains('InkWell(')));
    });

    test('de beschrijving is op een tv een tekstlink: niet vergroten, geen vak', () {
      final i = bron.indexOf('class _BioTextState');
      final lijf = bron.substring(i, bron.indexOf('class HeroCarousel', i));
      expect(lijf, contains('scaleOnFocus: !isTv,'));
      expect(lijf, contains('ringOnFocus: !isTv,'));
      expect(lijf, contains('tvLinkStijl('));
    });

    test('geen bronlabels op een tv', () {
      expect(bron, contains('final merk = !isTv && r.sources.length > 1'));
    });

    // Saber, 17-10-2026: "de menubar is te transparant, de tekst loopt door elkaar". Op alle vier de
    // pagina's die onder de balk door tekenen komt bij scrollen de donkere strook, ook op een tv.
    test('meeschuivend glas ook op een tv, en een capsule die bijna dicht is', () {
      expect('if (ruimte > 0 && !isTv)'.allMatches(bron).length, 0);
      expect(bron, isNot(contains('if (BalkRuimte.van(context) > 0 && !isTv)')));
      expect('if (ruimte > 0)\n'.allMatches(bron).length, 2);
      expect(bron, contains('if (BalkRuimte.van(context) > 0)\n'));
      final capsule = RegExp(r'const kTvMenuCapsule = BoxDecoration\(\s*color: Color\(0x([0-9A-F]{2})')
          .firstMatch(bron);
      expect(capsule, isNotNull);
      expect(int.parse(capsule!.group(1)!, radix: 16), greaterThanOrEqualTo(0xE0),
          reason: 'zonder vervaging leest tekst door een capsule van minder dan 88 % heen');
    });
  });
}
