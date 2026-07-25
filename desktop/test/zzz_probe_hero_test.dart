// Throwaway probe: is the hero banner's "Bekijken" button reachable with a remote?
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/tv.dart';

void main() {
  setUp(() {
    setTvModeForTest(true);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  });
  tearDown(() {
    setTvModeForTest(false);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  testWidgets('probe', (tester) async {
    final hits = [
      const CatalogAlbumHit(CatalogAlbum(1, 'Aaa', null, '2026-01-01', 10, 'album'), 'Artiest A'),
      const CatalogAlbumHit(CatalogAlbum(2, 'Bbb', null, '2026-02-01', 10, 'album'), 'Artiest B'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          SizedBox(height: 300, child: HeroCarousel(hits: hits)),
          ElevatedButton(onPressed: () {}, child: const Text('Onder')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    final btn = find.widgetWithText(FilledButton, 'Bekijken');
    debugPrint('Bekijken found: ${btn.evaluate().length}');
    if (btn.evaluate().isNotEmpty) {
      final node = Focus.maybeOf(tester.element(btn.first), scopeOk: false);
      debugPrint('nearest Focus canRequestFocus=${node?.canRequestFocus}');
    }

    // Enumerate every focusable node in the tree.
    final all = <FocusNode>[];
    void walk(FocusNode n) {
      all.add(n);
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(FocusManager.instance.rootScope);
    for (final n in all) {
      if (n.canRequestFocus && !n.skipTraversal) {
        debugPrint('FOCUSABLE: ${n.debugLabel ?? n.runtimeType} '
            'ctx=${n.context == null ? "none" : n.rect}');
      }
    }

    // Now: start on the button below the banner and press UP.
    final below = find.widgetWithText(ElevatedButton, 'Onder');
    Focus.of(tester.element(below.first)).requestFocus();
    await tester.pumpAndSettle();
    debugPrint('start = ${FocusManager.instance.primaryFocus?.debugLabel} '
        'rect=${FocusManager.instance.primaryFocus?.rect}');
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      final p = FocusManager.instance.primaryFocus;
      debugPrint('after UP #$i -> ${p?.debugLabel} rect=${p?.context == null ? "none" : p?.rect}');
    }
  });
}
