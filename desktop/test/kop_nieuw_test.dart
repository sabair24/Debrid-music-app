/// De artiestkop zoals Saber hem op 27-10-2026 goedkeurde in het ontwerp: de foto ook opzij te schuiven,
/// het logo van TheAudioDB in plaats van de grote naam, en een keuze tussen die twee in "Kop aanpassen".
///
/// Zijn woorden: "ik moet eerder de foto kunnen verschuiven in alle richtingen … ook de naam van de artist
/// is te groot, en die mag vervangen worden door de iconen naam die ook in de now palying wordt gebruikt",
/// en op het ontwerp: "het moet ook zijdelings verschoven kunnen worden".
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import 'package:debridmusic/beeldvorm.dart';
import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/ui/kop_logo.dart';
import 'package:debridmusic/ui/kopbewerker.dart';
import 'package:debridmusic/ui/kopfoto.dart';

/// Een logo zoals TheAudioDB ze heeft: een PNG met een doorzichtige achtergrond.
final _logo = Uint8List.fromList(img.encodePng(img.Image(width: 40, height: 12, numChannels: 4)));

/// Hetzelfde zonder alfa: zo'n logo zou in de kleur van de tekst een egaal blok worden.
final _dichtLogo = Uint8List.fromList(img.encodePng(img.Image(width: 40, height: 12)));

/// Een liggende foto (16:9): in een brede kop is hij vullend precies zo breed als de kop.
final _liggend = Uint8List.fromList(img.encodePng(img.Image(width: 160, height: 90)));

/// Een PNG-kop met alleen de blokken die [heeftDoorzichtigheid] leest.
Uint8List _pngMet({required int kleursoort, bool tRNS = false}) {
  final b = BytesBuilder();
  void blok(String soort, List<int> data) {
    final n = data.length;
    b.add([(n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255, ...soort.codeUnits, ...data, 0, 0, 0, 0]);
  }

  b.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  blok('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, kleursoort, 0, 0, 0]);
  if (tRNS) blok('tRNS', [0]);
  blok('IDAT', [0]);
  blok('IEND', []);
  return b.toBytes();
}

Uint8List _webp(String soort, {int vlaggen = 0}) => Uint8List.fromList([
      ...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits, ...soort.codeUnits, 10, 0, 0, 0, vlaggen, 0, 0, 0, //
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ]);

Widget _omhulsel(Widget kind) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
        ChangeNotifierProvider<AppSettings>(create: (_) => AppSettings()),
      ],
      child: MaterialApp(home: Scaffold(body: ListView(children: [kind]))),
    );

void main() {
  setUpAll(() {
    // Nooit in de echte appmap schrijven tijdens een toets.
    setAppDirForTest(Directory.systemTemp.createTempSync('kopnieuw').path);
  });

  group('welk logo in de kleur van de tekst kan', () {
    test('een PNG met alfa wel, zonder alfa niet, en een JPEG nooit', () {
      expect(heeftDoorzichtigheid(_logo), isTrue);
      expect(heeftDoorzichtigheid(_dichtLogo), isFalse);
      expect(heeftDoorzichtigheid(Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)))), isFalse);
    });

    test('een palet of RGB alleen met een tRNS-blok, en dat moet vóór de beelddata staan', () {
      expect(heeftDoorzichtigheid(_pngMet(kleursoort: 3, tRNS: true)), isTrue);
      expect(heeftDoorzichtigheid(_pngMet(kleursoort: 3)), isFalse);
      expect(heeftDoorzichtigheid(_pngMet(kleursoort: 2, tRNS: true)), isTrue);
      expect(heeftDoorzichtigheid(_pngMet(kleursoort: 6)), isTrue);
    });

    test('een WebP met de alfavlag of verliesvrij wel, een gewone niet; onzin nooit', () {
      expect(heeftDoorzichtigheid(_webp('VP8X', vlaggen: 0x10)), isTrue);
      expect(heeftDoorzichtigheid(_webp('VP8X')), isFalse);
      expect(heeftDoorzichtigheid(_webp('VP8L')), isTrue);
      expect(heeftDoorzichtigheid(_webp('VP8 ')), isFalse);
      expect(heeftDoorzichtigheid(Uint8List.fromList([1, 2, 3])), isFalse);
      expect(heeftDoorzichtigheid(Uint8List(0)), isFalse);
    });
  });

  group('opzij voorbij de rand', () {
    const vak = Size(1440, 764);
    const beeld = Size(1280, 720);
    const doel = Offset(.68, .4);

    test('zonder ruimte blijft hij vullend; met de ruimte mag tot 40 % van de breedte vrijkomen', () {
      // Het punt ver links in de foto op het doel: de foto wil naar rechts.
      const punt = Brandpunt(-.5, .5);
      final vullend = kopPlek(vak: vak, beeld: beeld, punt: punt, doel: doel);
      expect(vullend.left, 0, reason: 'zoals de app zelf kiest: nooit een rand');
      final vrij = kopPlek(vak: vak, beeld: beeld, punt: punt, doel: doel, opzij: kOpzijVrij);
      expect(vrij.left, closeTo(kOpzijVrij * vak.width, 1e-6));
      expect(vrij.top, vullend.top, reason: 'op en neer verandert er niets');
      final links = kopPlek(vak: vak, beeld: beeld, punt: const Brandpunt(1.5, .5), doel: doel, opzij: kOpzijVrij);
      expect(links.right, closeTo(vak.width * (1 - kOpzijVrij), 1e-6));
    });

    test('op en neer blijft hij altijd vullend — daar zou vrijlaten lege ruimte zijn', () {
      final r = kopPlek(vak: vak, beeld: beeld, punt: const Brandpunt(.5, -1), doel: doel, opzij: kOpzijVrij);
      expect(r.top, 0);
      final s = kopPlek(vak: vak, beeld: beeld, punt: const Brandpunt(.5, 2), doel: doel, opzij: kOpzijVrij);
      expect(s.bottom, closeTo(vak.height, 1e-6));
    });

    test('een zachte rand alleen aan de kant die vrijkomt', () {
      expect(randenVan(const Rect.fromLTWH(0, 0, 1440, 810), vak), (links: 0.0, rechts: 0.0, boven: 0.0, onder: 0.0));
      final rechts = randenVan(const Rect.fromLTWH(300, 0, 1440, 810), vak);
      expect(rechts.links, greaterThan(0));
      expect(rechts.rechts, 0, reason: 'rechts loopt de foto nog voorbij de rand');
      final links = randenVan(const Rect.fromLTWH(-300, 0, 1440, 810), vak);
      expect(links.links, 0);
      expect(links.rechts, greaterThan(0));
    });

    test('een eigen instelling krijgt de ruimte, wat de app zelf kiest niet', () {
      const i = KopInstelling(fx: -.3, fy: .4);
      final eigen = KopFoto.plekVoor(vak: vak, maat: beeld, blik: null, instelling: i, smal: false);
      expect(eigen.left, greaterThan(0));
      final zelf = KopFoto.plekVoor(vak: vak, maat: beeld, blik: null, instelling: null, smal: false);
      expect(zelf.left, lessThanOrEqualTo(0));
      expect(zelf.right, greaterThanOrEqualTo(vak.width));
    });

    test('puntOpDoel en kopPlek blijven elkaars omgekeerde, ook naast de foto', () {
      // 1,05: de foto staat zo ver naar links dat de vaste plek rechts naast hem ligt.
      final plek = kopPlek(vak: vak, beeld: beeld, punt: const Brandpunt(1.05, .4), doel: doel, opzij: kOpzijVrij);
      expect(plek.right, lessThan(doel.dx * vak.width), reason: 'de vaste plek ligt naast de foto');
      final terug = puntOpDoel(vak: vak, plek: plek, doel: doel);
      expect(terug.x, closeTo(1.05, 1e-6));
      expect(terug.y, closeTo(.4, 1e-6));
    });
  });

  group("scherp en vrij (Saber, 27-10-2026: 'waarom worden foto's zo uitgerokken')", () {
    // Claude François: 1496 × 1994 van Wikipedia, op zijn scherm van 2560 punten (dpr 1) 1,7 keer opgerekt.
    const bron = Size(1496, 1994);
    const vak = Size(2560, 1242);
    const doel = Offset(.68, .3);

    test('nooit meer dan 1,25 keer: kleiner dan de breedte, rechts tegen de rand, op en neer vullend', () {
      final grens = scherpteGrens(tot: kScherpTot, bron: bron, maat: bron, vak: vak.width, pixels: 2560);
      expect(grens, closeTo(1.25, 1e-9));
      final r = kopPlek(vak: vak, beeld: bron, punt: Brandpunt.midden, doel: doel, maxSchaal: grens);
      expect(r.width, closeTo(1496 * 1.25, 1e-6));
      expect(r.right, closeTo(vak.width, 1e-6), reason: 'de app zet hem rechts, waar de naam niet staat');
      expect(r.top, lessThanOrEqualTo(0));
      expect(r.bottom, greaterThanOrEqualTo(vak.height));
      expect(randenVan(r, vak).links, greaterThan(0), reason: 'links loopt hij zacht over in de achtergrond');
    });

    test('de grens rekent met de echte pixels, ook als de foto verkleind bekeken is', () {
      // Een bekeken foto heeft de maat van zijn verkleinde versie (480 lang), de bron die van het bestand.
      final viaBlik = scherpteGrens(tot: kScherpTot, bron: bron, maat: const Size(360, 480), vak: 2560, pixels: 2560);
      expect(360 * viaBlik!, closeTo(1496 * 1.25, 1), reason: 'dezelfde breedte op het scherm');
      // Een Mac tekent twee pixels per punt: dezelfde foto wordt daar half zo breed in punten.
      final mac = scherpteGrens(tot: kScherpTot, bron: bron, maat: bron, vak: 1440, pixels: 2880);
      expect(1496 * mac!, closeTo(1496 * 1.25 / 2, 1e-6));
      expect(scherpteGrens(tot: kScherpTot, bron: null, maat: bron, vak: 2560, pixels: 2560), isNull);
    });

    test('een te kleine foto vult op en neer toch, ook boven de grens', () {
      const klein = Size(339, 510);
      final grens = scherpteGrens(tot: kScherpTot, bron: klein, maat: klein, vak: 2560, pixels: 2560);
      final r = kopPlek(vak: const Size(2560, 640), beeld: klein, punt: Brandpunt.midden, doel: doel, maxSchaal: grens);
      expect(r.height, greaterThanOrEqualTo(640));
    });

    test('een scherpe foto vult gewoon, zoals altijd', () {
      const groot = Size(3840, 2160);
      final grens = scherpteGrens(tot: kScherpTot, bron: groot, maat: groot, vak: 2560, pixels: 2560);
      final r = kopPlek(vak: const Size(2560, 640), beeld: groot, punt: Brandpunt.midden, doel: doel, maxSchaal: grens);
      expect(r.left, lessThanOrEqualTo(0));
      expect(r.right, greaterThanOrEqualTo(2560));
    });

    test('kleiner dan vullend: hij staat helemaal in de kop, met zachte randen waar hij vrijkomt', () {
      const i = KopInstelling(fx: .5, fy: .5, zoom: .5);
      const pc = Size(1440, 764);
      final r = KopFoto.plekVoor(vak: pc, maat: const Size(1280, 720), blik: null, instelling: i, smal: false);
      expect(r.width, closeTo(1440 * .5, 1e-6));
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(pc.height + 1e-6));
      final randen = randenVan(r, pc);
      expect(randen.boven + randen.onder, greaterThan(0));
      expect(randen.links + randen.rechts, greaterThan(0));
      expect(KopInstelling.lees(i.schrijf()), i, reason: 'een zoom onder 1 reist mee');
    });

    testWidgets('een eigen hoogte nooit hoger dan het venster: de knoppen blijven in beeld', (t) async {
      t.view.physicalSize = const Size(1440, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_omhulsel(EditorialeKop(
        naam: 'Claude François',
        bovenBloed: 64,
        uitsnede: const KopInstelling(fx: .49, fy: .26, hoogte: 1357),
        actions: [FilledButton(onPressed: () {}, child: const Text('Radio'))],
      )));
      await t.pump();
      expect(t.getRect(find.byType(EditorialeKop)).height, lessThanOrEqualTo(1000 - 110 + 1));
      expect(t.getRect(find.widgetWithText(FilledButton, 'Radio')).bottom, lessThan(1000 - 96));
    });

    testWidgets('scherp op een breed scherm, vullend op een gsm', (t) async {
      for (final (breed, grens) in [(1440.0, kScherpTot), (411.0, null)]) {
        t.view.physicalSize = Size(breed, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(_omhulsel(EditorialeKop(naam: 'Amy Winehouse', art: ArtistArt(backdropBytes: _liggend))));
        await t.pump();
        expect(t.widget<KopFoto>(find.byType(KopFoto)).scherpTot, grens, reason: 'op $breed punten');
      }
    });
  });

  group('de kop toont het logo', () {
    void pc(WidgetTester t) {
      t.view.physicalSize = const Size(1440, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
    }

    testWidgets('met een doorzichtig logo het logo, in de kleur van de tekst, en niet de naam', (t) async {
      pc(t);
      await t.pumpWidget(_omhulsel(EditorialeKop(naam: 'Amy Winehouse', art: ArtistArt(logoBytes: _logo))));
      await t.pump();
      expect(find.byType(KopLogo), findsOneWidget);
      expect(find.textContaining('AMY'), findsNothing);
      final beeld = t.widget<Image>(find.descendant(of: find.byType(KopLogo), matching: find.byType(Image)));
      expect(beeld.colorBlendMode, BlendMode.srcIn, reason: 'wit op een lichte pagina zie je niet');
    });

    testWidgets('koos je de naam, of is het logo dicht, dan de naam', (t) async {
      pc(t);
      await t.pumpWidget(_omhulsel(EditorialeKop(
        naam: 'Amy Winehouse',
        art: ArtistArt(logoBytes: _logo),
        uitsnede: const KopInstelling(fx: .5, fy: .3, naam: true),
      )));
      await t.pump();
      expect(find.byType(KopLogo), findsNothing);
      expect(find.textContaining('AMY'), findsOneWidget);

      await t.pumpWidget(_omhulsel(EditorialeKop(naam: 'Amy Winehouse', art: ArtistArt(logoBytes: _dichtLogo))));
      await t.pump();
      expect(find.byType(KopLogo), findsNothing);
      expect(find.textContaining('AMY'), findsOneWidget);
    });

    testWidgets('de naam is op een bureaublad 64 en niet meer 132', (t) async {
      pc(t);
      await t.pumpWidget(_omhulsel(const EditorialeKop(naam: 'Amy Winehouse')));
      await t.pump();
      expect(t.widget<Text>(find.textContaining('AMY')).style?.fontSize, 64);
      expect(find.text('AMY WINEHOUSE'), findsOneWidget, reason: 'op die maat past hij op één regel');
    });
  });

  test('Foto kiezen wacht op het bewaren en toont waarom het mislukte', () {
    // Op een Mac gaat de keuze naar de pc. De klik wachtte daar niet op, dus een fout verdween ongezien.
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main, contains('      onPressed: () => _kies(soort, img.uri),\n'));
    expect(main, contains('      await lib.setArtistArt(widget.artist, soort, adres);\n'));
    expect(main, contains("      if (mounted) setState(() => _keuzeFout = 'Niet bewaard: \$e');\n"));
    expect(main, contains('              if (_keuzeFout != null) ...[\n'));
    expect(main, isNot(contains('onPressed: () => lib.setArtistArt(widget.artist, soort, img.uri),')));
  });

  group('Kop aanpassen', () {
    Future<List<(KopScherm, KopInstelling?)>> open(WidgetTester t, {Uint8List? logo}) async {
      t.view.physicalSize = const Size(1400, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final bewaard = <(KopScherm, KopInstelling?)>[];
      await t.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: KopBewerker(
            naam: 'Amy Winehouse',
            beeld: _liggend,
            huidig: const {},
            bronMaat: const Size(160, 90),
            logo: logo,
            bewaar: (s, i) async => bewaard.add((s, i)),
          ),
        ),
      ));
      await t.pump();
      return bewaard;
    }

    testWidgets('een liggende foto schuift opzij zonder in te zoomen', (t) async {
      final bewaard = await open(t);
      // Vullend is hij in een brede kop precies zo breed als de kop: vroeger bewoog hij opzij niet.
      await t.drag(find.byKey(const ValueKey('kop-foto')), const Offset(150, 0));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('kop-opslaan')));
      await t.pump();
      final i = bewaard.single.$2!;
      expect(i.zoom, 1);
      const vak = Size(1440, 700);
      final plek = KopFoto.plekVoor(vak: vak, maat: const Size(160, 90), blik: null, instelling: i, smal: false, bovenRand: 64);
      expect(plek.left, greaterThan(0), reason: 'de foto staat naar rechts, met links een zachte rand');
    });

    testWidgets('met een logo kies je logo of naam, en dat wordt bewaard', (t) async {
      final bewaard = await open(t, logo: _logo);
      expect(find.byKey(const ValueKey('kop-toont-logo')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('kop-toont-naam')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('kop-opslaan')));
      await t.pump();
      expect(bewaard.single.$1, KopScherm.pc);
      expect(bewaard.single.$2!.naam, isTrue);
    });

    testWidgets('met knoppen kleiner dan vullend en een stap opzij — ook met een afstandsbediening', (t) async {
      final bewaard = await open(t);
      for (var k = 0; k < 4; k++) {
        await t.tap(find.byKey(const ValueKey('kop-kleiner')));
        await t.pump();
      }
      await t.tap(find.byKey(const ValueKey('kop-rechts')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('kop-opslaan')));
      await t.pump();
      final i = bewaard.single.$2!;
      expect(i.zoom, lessThan(1), reason: 'verkleinen mag');
      expect(i.zoom, closeTo(1 / (1.1 * 1.1 * 1.1 * 1.1), 1e-3));
    });

    testWidgets('zonder bruikbaar logo geen keuze', (t) async {
      await open(t, logo: _dichtLogo);
      expect(find.byKey(const ValueKey('kop-toont-logo')), findsNothing);
    });
  });
}
