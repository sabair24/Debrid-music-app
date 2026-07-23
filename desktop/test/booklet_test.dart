import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:debridmusic/booklet.dart';
import 'package:debridmusic/booklet_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Michael Jackson — Bad, at the pixel dimensions the archives actually hold: eleven scans,
/// of which the eight booklet sheets are two pages photographed together. The spread rule is
/// exercised against the case it was written for, including the rear inlay at 1.26:1 — wider
/// than tall, and still one page.
const _bad = [
  ('front', 1200, 1194),
  ('booklet', 1200, 602),
  ('booklet', 1200, 609),
  ('booklet', 1200, 610),
  ('booklet', 1200, 612),
  ('booklet', 1200, 607),
  ('booklet', 1200, 606),
  ('booklet', 1200, 604),
  ('booklet', 1200, 602),
  ('disc', 1200, 1196),
  ('back', 1200, 952),
];

BookletSheet _sheet(String kind, int w, int h) => BookletSheet(
  uri: '',
  thumbUri: '',
  width: w,
  height: h,
  kind: switch (kind) {
    'front' => SheetKind.front,
    'disc' => SheetKind.disc,
    'back' => SheetKind.back,
    _ => SheetKind.booklet,
  },
);

Booklet _booklet({String dir = ''}) => Booklet(
  releaseId: 1,
  dirPath: dir,
  sheets: [for (final (k, w, h) in _bad) _sheet(k, w, h)],
);

// Each sheet is painted in colours that say which sheet it is and which half you are looking
// at, so the render tests can assert the windowing instead of eyeballing it.
img.ColorRgb8 _left(int i) => img.ColorRgb8(200, 20 * i, 0);
img.ColorRgb8 _right(int i) => img.ColorRgb8(0, 20 * i, 200);

void main() {
  group('sheets and pages', () {
    test('a scan is a spread on its shape, not on what Discogs calls it', () {
      final b = _booklet();
      expect(b.sheets[0].spread, isFalse, reason: 'sleeve front, 1.005:1');
      expect(b.sheets[1].spread, isTrue, reason: 'booklet sheet, 1.99:1');
      expect(b.sheets[9].spread, isFalse, reason: 'disc, 1.003:1');
      expect(
        b.sheets[10].spread,
        isFalse,
        reason: 'rear inlay is 1.26:1 — wider than tall, but one page',
      );
    });

    test('eleven scans make nineteen pages', () {
      expect(_booklet().pages.length, 19);
    });

    test('each spread yields a left and a right, each single yields one whole page', () {
      final p = _booklet().pages;
      expect(p[0].half, Half.whole); // front
      expect(p[1].half, Half.left); // first booklet sheet
      expect(p[2].half, Half.right);
      expect(p[17].half, Half.whole); // disc
      expect(p[18].half, Half.whole); // back
      expect(p[18].sheet, 10);
    });

    test('a page slot is very nearly square, taken from the spreads', () {
      expect(_booklet().pageAspect, closeTo(0.99, 0.02));
    });

    test('only a step between two spreads turns a leaf', () {
      final b = _booklet();
      expect(b.turns(0, 1), isFalse, reason: 'sleeve front is not a leaf of the booklet');
      expect(b.turns(1, 2), isTrue);
      expect(b.turns(7, 8), isTrue);
      expect(b.turns(8, 9), isFalse, reason: 'last sheet to the disc');
      expect(b.turns(9, 10), isFalse, reason: 'disc to the rear inlay');
      expect(b.turns(0, 99), isFalse, reason: 'off the end');
    });

    test('a release with only a front cover still works', () {
      final b = Booklet(releaseId: 1, sheets: [_sheet('front', 600, 598)]);
      expect(b.pages.length, 1);
      expect(b.pageAspect, closeTo(1.0, 0.02));
      expect(b.turns(0, 1), isFalse);
    });
  });

  group('rendering', () {
    late Directory dir;

    setUpAll(() {
      // Stand-ins rather than real scans: album artwork is not ours to commit, and flat
      // colours make the assertions exact — a red left slot can only be a left half.
      dir = Directory.systemTemp.createTempSync('booklet_render');
      for (var i = 0; i < _bad.length; i++) {
        final (_, w, h) = _bad[i];
        final im = img.Image(width: w, height: h);
        if (w / h >= kSpreadRatio) {
          img.fillRect(im, x1: 0, y1: 0, x2: w ~/ 2 - 1, y2: h - 1, color: _left(i));
          img.fillRect(im, x1: w ~/ 2, y1: 0, x2: w - 1, y2: h - 1, color: _right(i));
        } else {
          img.fill(im, color: _left(i));
        }
        final png = img.encodePng(im);
        final n = i.toString().padLeft(2, '0');
        File('${dir.path}/$n').writeAsBytesSync(png);
        File('${dir.path}/${n}t').writeAsBytesSync(png);
      }
      Directory('build').createSync(recursive: true);
    });

    tearDownAll(() => dir.deleteSync(recursive: true));

    /// Pump the booklet at a desktop window size and hand back what it drew.
    ///
    /// [dragBy] leaves a real drag half-finished, which is the only way to catch the leaf
    /// mid-turn — and it goes through the drag handler rather than a test-only back door.
    Future<({ByteData pixels, int width})> shoot(
      WidgetTester tester,
      String name,
      int page, {
      double dragBy = 0,
    }) async {
      final key = GlobalKey();
      final b = _booklet(dir: dir.path);

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: key,
            child: BookletView(
              booklet: b,
              title: 'Bad',
              initialPage: page,
              fetch: (i) async => b.sheetFile(i),
            ),
          ),
        ),
      );

      // Image.file decodes asynchronously; without real async time the pages stay blank.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }

      if (dragBy != 0) {
        final g = await tester.startGesture(const Offset(940, 430));
        for (var i = 0; i < 6; i++) {
          await g.moveBy(Offset(dragBy / 6, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }

      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      File('build/booklet_$name.png').writeAsBytesSync(
        (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List(),
      );
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (pixels: raw!, width: image.width);
    }

    ({int r, int g, int b}) at(({ByteData pixels, int width}) shot, int x, int y) {
      final o = (y * shot.width + x) * 4;
      return (
        r: shot.pixels.getUint8(o),
        g: shot.pixels.getUint8(o + 1),
        b: shot.pixels.getUint8(o + 2),
      );
    }

    testWidgets('a spread shows its own two halves, each on the correct side', (tester) async {
      await tester.runAsync(() async {
        final shot = await shoot(tester, 'spread', 3); // page 3 → sheet 2

        // Well inside each slot, clear of the crease and the edges.
        final left = at(shot, 340, 430);
        final right = at(shot, 940, 430);

        expect(left.r, greaterThan(150), reason: 'left slot must be sheet 2\'s LEFT half (red)');
        expect(left.b, lessThan(80));
        expect(right.b, greaterThan(150), reason: 'right slot must be sheet 2\'s RIGHT half (blue)');
        expect(right.r, lessThan(80));

        // 20*2 in the green channel is what says "sheet 2" rather than a neighbour.
        expect(left.g, closeTo(40, 12));
        expect(right.g, closeTo(40, 12));
      });
    });

    testWidgets('an unsplit scan is centred on the spine, not boxed into one slot', (tester) async {
      await tester.runAsync(() async {
        final shot = await shoot(tester, 'back', 18); // the rear inlay, 1.26:1

        // It is wider than a page slot, so it must cover the middle AND reach past where the
        // right slot begins — the failure this guards against is it shrinking into one half.
        expect(at(shot, 640, 430).r, greaterThan(150), reason: 'covers the spine');
        expect(at(shot, 780, 430).r, greaterThan(150), reason: 'reaches into the right slot');
        expect(at(shot, 500, 430).r, greaterThan(150), reason: 'reaches into the left slot');
      });
    });

    testWidgets('the sleeve front renders', (tester) async {
      await tester.runAsync(() async {
        final shot = await shoot(tester, 'front', 0);
        expect(at(shot, 640, 430).r, greaterThan(150));
      });
    });

    testWidgets('a drag lifts the leaf and uncovers the next sheet', (tester) async {
      await tester.runAsync(() async {
        // From page 3 (sheet 2) dragging left starts a turn onto sheet 3.
        final shot = await shoot(tester, 'turn', 3, dragBy: -260);

        // The left page is untouched: still sheet 2's left half.
        expect(at(shot, 340, 430).r, greaterThan(150));

        // Behind the lifted leaf sits the NEXT sheet's right half — sheet 3, so green ≈ 60,
        // where before the drag that spot was sheet 2's right half at green ≈ 40.
        final uncovered = at(shot, 1150, 430);
        expect(uncovered.b, greaterThan(150), reason: 'a right half is showing');
        expect(uncovered.g, closeTo(60, 12), reason: 'and it belongs to sheet 3, not sheet 2');
      });
    });
  });
}
