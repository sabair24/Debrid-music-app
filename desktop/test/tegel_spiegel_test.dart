// De spiegeling en de diepere schaduw onder elke albumtegel (Saber, 19-10-2026: "volle spiegeling",
// variant B, overal waar albumtegels staan, ook op tv). De kern is de kosten: één keer bakken per hoes,
// geen tweede decodering, en daarna één plat beeld per tegel.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:debridmusic/artwork.dart' show decodeWidth;
import 'package:debridmusic/ui/maten.dart';
import 'package:debridmusic/ui/tegel.dart';
import 'package:debridmusic/ui/tegel_spiegel.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Een hoes: boven rood, onder blauw. De spiegeling hoort alleen blauw te tonen.
Uint8List _hoes() {
  final b = img.Image(width: 40, height: 40);
  for (var x = 0; x < 40; x++) {
    for (var y = 0; y < 40; y++) {
      if (y < 20) {
        b.setPixelRgba(x, y, 255, 0, 0, 255);
      } else {
        b.setPixelRgba(x, y, 0, 0, 255, 255);
      }
    }
  }
  return Uint8List.fromList(img.encodePng(b));
}

/// Zoals `cover` in main.dart een hoes tekent.
Widget _cover(Uint8List b, double maat) => ClipRRect(
      borderRadius: BorderRadius.circular(kHoek12),
      child: Image.memory(b, width: maat, height: maat, fit: BoxFit.cover, cacheWidth: decodeWidth(maat)),
    );

Future<void> _wachtOpSpiegel(WidgetTester t) async {
  for (var i = 0; i < 40 && find.byKey(const ValueKey('tegel-spiegel')).evaluate().isEmpty; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
}

/// Tekent de spiegeling van [_hoes] in een beeld van 100 × 22 en geeft de pixels terug.
Future<ByteData> _spiegelPixels(WidgetTester t, {double hoek = 0}) async => (await t.runAsync(() async {
      final codec = await ui.instantiateImageCodec(_hoes());
      final bron = (await codec.getNextFrame()).image;
      final opname = ui.PictureRecorder();
      tekenSpiegel(Canvas(opname), bron, maat: 100, hoogte: 22, hoek: hoek);
      final beeld = await opname.endRecording().toImage(100, 22);
      return beeld.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    }))!;

void main() {
  setUp(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  testWidgets('de onderkant omgekeerd, van 20 % naar niets', (t) async {
    final p = await _spiegelPixels(t);
    int px(int x, int y, int k) => p.getUint8((y * 100 + x) * 4 + k);
    // Bovenaan: blauw (de onderrand van de hoes), op een vijfde dekking.
    expect(px(50, 0, 2), greaterThan(200), reason: 'blauw');
    expect(px(50, 0, 0), lessThan(40), reason: 'geen rood: alleen de onderste 22 % wordt gespiegeld');
    expect(px(50, 0, 3), closeTo(51, 8), reason: '20 % dekking bovenaan');
    expect(px(50, 11, 3), allOf(greaterThan(10), lessThan(40)), reason: 'halverwege minder');
    expect(px(50, 21, 3), lessThan(4), reason: 'onderaan niets meer');
  });

  testWidgets('afgerond zoals de hoes: in de hoeken bovenaan niets', (t) async {
    final p = await _spiegelPixels(t, hoek: 12);
    expect(p.getUint8((0 * 100 + 0) * 4 + 3), lessThan(6), reason: 'de hoek');
    expect(p.getUint8((0 * 100 + 50) * 4 + 3), greaterThan(40), reason: 'het midden');
  });

  testWidgets('DE STREEP (Saber, 19-10-2026): onderaan een grote spiegeling niets, en geen treden', (t) async {
    final p = (await t.runAsync(() async {
      final codec = await ui.instantiateImageCodec(_hoes());
      final bron = (await codec.getNextFrame()).image;
      final opname = ui.PictureRecorder();
      tekenSpiegel(Canvas(opname), bron, maat: 300, hoogte: 70, hoek: 10);
      final beeld = await opname.endRecording().toImage(300, 70);
      return beeld.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    }))!;
    int a(int y) => p.getUint8((y * 300 + 150) * 4 + 3);
    for (var y = 65; y < 70; y++) {
      expect(a(y), 0, reason: 'rij $y: de onderrand van het vak tekent niets');
    }
    for (var y = 1; y < 64; y++) {
      expect((a(y) - a(y - 1)).abs(), lessThanOrEqualTo(3), reason: 'rij $y: geen zichtbare trede');
    }
    expect(spiegelStroken(70), greaterThanOrEqualTo(24));
  });

  test('de grote hoes gebruikt dezelfde stroken, maar gebakken; geen ShaderMask', () {
    final bron = File('lib/ui/kantel_hoes.dart').readAsStringSync();
    final lijf = bron.substring(bron.indexOf('class HoesSpiegel'));
    // Gebakken sinds 23-10-2026: in stroken kostte hij op de Mac 7 ms per beeld (zie TegelSpiegel.gebakken).
    expect(lijf, contains("TegelSpiegel(bron: MemoryImage(beeld), maat: maat, hoek: 10, gebakken: !zonderVoorMeting('stroken'))"));
    expect(lijf, isNot(contains('ShaderMask(')));
  });

  test('gebakken: precies wat de stroken tekenen, op schermresolutie', () async {
    final rood = ui.PictureRecorder();
    final c = Canvas(rood);
    c.drawRect(const Rect.fromLTWH(0, 0, 40, 20), Paint()..color = const Color(0xFFFF0000));
    c.drawRect(const Rect.fromLTWH(0, 20, 40, 20), Paint()..color = const Color(0xFF0000FF));
    final hoes = rood.endRecording().toImageSync(40, 40);
    final gebakken = bakSpiegel(hoes, maat: 100, hoek: 10, dpr: 2);
    expect(gebakken.width, 200);
    expect(gebakken.height, (100 * kTegelSpiegelHoogte * 2).ceil());
    final los = ui.PictureRecorder();
    tekenSpiegel(Canvas(los)..scale(2), hoes, maat: 100, hoogte: 100 * kTegelSpiegelHoogte, hoek: 10);
    final direct = los.endRecording().toImageSync(gebakken.width, gebakken.height);
    final a = (await gebakken.toByteData())!.buffer.asUint8List();
    final b = (await direct.toByteData())!.buffer.asUint8List();
    expect(a, b, reason: 'hetzelfde beeld, alleen één keer getekend');
    expect(a.any((x) => x != 0), isTrue, reason: 'anders bewijst dit niets');
  });

  testWidgets('gebakken: één beeld in plaats van de stroken, en opnieuw bij een andere maat', (t) async {
    final b = _hoes();
    Widget bouw(double maat) => MaterialApp(
        home: Center(
            child: SizedBox(
                width: maat,
                height: maat * kTegelSpiegelHoogte,
                child: TegelSpiegel(bron: MemoryImage(b), maat: maat, hoek: 10, gebakken: true))));
    await t.pumpWidget(bouw(120));
    for (var i = 0; i < 40 && find.byKey(const ValueKey('tegel-spiegel-gebakken')).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    expect(find.byKey(const ValueKey('tegel-spiegel-gebakken')), findsOneWidget);
    expect(find.byKey(const ValueKey('tegel-spiegel')), findsNothing, reason: 'geen stroken meer per beeld');
    final eerst = t.widget<RawImage>(find.byType(RawImage)).image!;
    expect(eerst.width, (120 * t.view.devicePixelRatio).ceil());
    await t.pumpWidget(bouw(160));
    await t.pump();
    final daarna = t.widget<RawImage>(find.byType(RawImage)).image!;
    expect(daarna.width, (160 * t.view.devicePixelRatio).ceil(), reason: 'een andere maat bakt opnieuw');
  });

  test('dezelfde bron als de hoes: geen tweede decodering', () async {
    final b = _hoes();
    const cfg = ImageConfiguration.empty;
    expect(await ResizeImage(spiegelVan(b)!, width: 280).obtainKey(cfg),
        await Image.memory(b, cacheWidth: 280).image.obtainKey(cfg));
    expect(await ResizeImage(spiegelVanUrl('https://e.x/h.jpg')!, width: 280).obtainKey(cfg),
        await Image.network('https://e.x/h.jpg', cacheWidth: 280).image.obtainKey(cfg));
    expect(spiegelVan(null), isNull);
    expect(spiegelVanUrl(''), isNull);
  });

  group('op de tegel', () {
    Future<void> zet(WidgetTester t, Uint8List b, {int tegels = 1, bool spiegel = true}) async {
      await t.pumpWidget(MaterialApp(
        home: Material(
          child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < tegels; i++)
                AlbumTegel(
                  key: ValueKey('tegel-$i'),
                  hoes: (m) => _cover(b, m),
                  spiegel: spiegel ? spiegelVan(b) : null,
                  breedte: 140,
                  titel: 'Thriller',
                  ondertitel: 'Michael Jackson',
                  onTap: () {},
                ),
            ]),
          ),
        ),
      ));
      await _wachtOpSpiegel(t);
    }

    testWidgets('onder de hoes, zo breed als de hoes, en de titel staat erover', (t) async {
      await zet(t, _hoes());
      final s = find.byKey(const ValueKey('tegel-spiegel'));
      expect(s, findsOneWidget);
      final hoes = t.getRect(find.byType(Image));
      final r = t.getRect(s);
      expect(r.top, closeTo(hoes.bottom + kTegelSpiegelAfstand, .01));
      expect(r.width, closeTo(140, .01));
      expect(r.height, closeTo(140 * kTegelSpiegelHoogte, .01));
      // De titel ligt in hetzelfde vlak, en tekent later: hij staat erover.
      expect(t.getRect(find.text('Thriller')).overlaps(r), isTrue);
      final volgorde = find.byWidgetPredicate(
          (w) => w.key == const ValueKey('tegel-spiegel') || (w is RichText && w.text.toPlainText() == 'Thriller'));
      expect(t.widgetList(volgorde).first, isA<CustomPaint>(), reason: 'eerst de spiegeling, dan de titel');
    });

    testWidgets('DE KERN: geen laag, geen eigen beeld, en de hoes één keer gedecodeerd', (t) async {
      final b = _hoes();
      await zet(t, b, tegels: 3);
      final s = find.byKey(const ValueKey('tegel-spiegel'));
      expect(s, findsNWidgets(3));
      expect(PaintingBinding.instance.imageCache.currentSize, 1, reason: 'de spiegeling decodeert niets extra');
      final ro = t.renderObject(s.first);
      // Negen vlakjes uit de textuur van de hoes (de tiende ligt voorbij 92 %, daar is niets meer), binnen
      // één afgeronde knip. Geen saveLayer: die zou in elk beeld van elke tegel een eigen laag mengen.
      final n = spiegelStroken(140 * kTegelSpiegelHoogte);
      final zichtbaar = [for (var i = 0; i < n; i++) if ((i + .5) / n < .92) i].length;
      expect(ro, paintsExactlyCountTimes(#drawRect, zichtbaar));
      expect(ro, paintsExactlyCountTimes(#saveLayer, 0));
      expect(ro, paintsExactlyCountTimes(#clipRRect, 1));
    });

    testWidgets('zonder bron geen spiegeling', (t) async {
      await zet(t, _hoes(), spiegel: false);
      expect(find.byKey(const ValueKey('tegel-spiegel')), findsNothing);
    });

    testWidgets('de diepere schaduw, en aangewezen nog dieper', (t) async {
      await zet(t, _hoes());
      BoxDecoration deco() => t.widget<AnimatedContainer>(find.byType(AnimatedContainer)).decoration! as BoxDecoration;
      expect(deco().boxShadow, kSchaduwTegel);
      final muis = await t.createGesture(kind: PointerDeviceKind.mouse);
      await muis.addPointer(location: Offset.zero);
      addTearDown(muis.removePointer);
      await muis.moveTo(t.getCenter(find.byType(Image)));
      await t.pump();
      expect(deco().boxShadow, kSchaduwTegelAan);
    });
  });

  test('dieper dan de oude schaduw', () {
    expect(kSchaduwTegel.last.offset.dy, greaterThan(kSchaduw1.last.offset.dy));
    expect(kSchaduwTegel.last.blurRadius, greaterThan(kSchaduw1.last.blurRadius));
    expect(kSchaduwTegelAan.last.offset.dy, greaterThan(kSchaduwTegel.last.offset.dy));
  });

  test('aangesloten: overal waar albumtegels staan', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    for (final regel in [
      'spiegel: spiegelVan(a.cover),', // Albums, artiestpagina "in mijn bibliotheek", tv
      'spiegel: spiegelVan(albums[i].cover),', // rijen op Start
      'spiegel: spiegelVanUrl(hits[i].album.cover),', // Top van dit moment, Nieuw van jouw artiesten
      'spiegel: spiegelVanUrl(items[i].hit.album.cover),', // de rij van het taalmodel
      'spiegel: spiegelVanUrl(ts[i].cover),', // aanbevelingen
      'spiegel: spiegelVanUrl(u.album.cover),', // nieuwe releases
      'spiegel: spiegelVanUrl(t.cover),', // Ontdek
      'spiegel: spiegelVanUrl(h.album.cover),', // zoeken
      'spiegel: spiegelVanUrl(al.cover),', // discografie op de artiestpagina
      'spiegel: spiegelVanUrl(hit.album.cover),', // een stijlpagina
    ]) {
      expect(main, contains(regel));
    }
    expect('spiegel: spiegel,'.allMatches(main).length, 2, reason: '_card → _HoverCard → AlbumTegel');
    final tegel = File('lib/ui/tegel.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(tegel, contains('spiegelOnderHoes(bron: widget.spiegel, maat: maat, hoek: kHoek12, zichtbaar: _draai.voorInRust.value),'),
        reason: 'weg zolang de achterkant voor staat');
  });
}
