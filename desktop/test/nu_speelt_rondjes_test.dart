/// De ronde artiestportretjes vóór de naam op Nu speelt, zoals Tidal (Saber, 17-10-2026): alle
/// artiesten tot vier, elk aanklikbaar, en op een tv met OMHOOG vanaf de hoes te kiezen.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/settings.dart';

Widget _inVak(Widget kind, {double breedte = 420}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
        ChangeNotifierProvider<AppSettings>(create: (_) => AppSettings()),
      ],
      child: MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: breedte, child: kind)))),
    );

const _stijl = TextStyle(fontSize: 15);

void main() {
  testWidgets('één rondje per artiest, ook de gast uit de titel', (t) async {
    await t.pumpWidget(_inVak(const ArtistLine(
        artist: 'Lady Gaga', title: 'Telephone (feat. Beyoncé)', style: _stijl, rondjes: true)));
    await t.pump();
    expect(find.byKey(const ValueKey('np-rondje-Lady Gaga')), findsOneWidget);
    expect(find.byKey(const ValueKey('np-rondje-Beyoncé')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('hoogstens vier rondjes, en de namen ernaast lopen niet over', (t) async {
    const namen = ['Een', 'Twee', 'Drie', 'Vier', 'Vijf', 'Zes'];
    await t.pumpWidget(_inVak(const ArtiestRondjes(namen: namen), breedte: 300));
    await t.pump();
    for (final n in namen.take(4)) {
      expect(find.byKey(ValueKey('np-rondje-$n')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('np-rondje-Vijf')), findsNothing);

    await t.pumpWidget(_inVak(
        const ArtistLine(
            artist: 'At The Villa People, Etienne Vandewiele, Bruno Quatresous',
            title: 'Een titel',
            style: _stijl,
            omvouwen: true,
            rondjes: true),
        breedte: 260));
    await t.pump();
    expect(t.takeException(), isNull, reason: 'een overloop meldt zich als fout');
  });

  testWidgets('zonder rondjes blijft de regel wat hij was', (t) async {
    await t.pumpWidget(_inVak(const ArtistLine(artist: 'Portishead', title: 'Roads', style: _stijl)));
    await t.pump();
    expect(find.byType(ArtiestRondjes), findsNothing);
  });

  testWidgets('de eerste kan de selectie krijgen — daar gaat OMHOOG vanaf de hoes naartoe', (t) async {
    final eerste = FocusNode();
    addTearDown(eerste.dispose);
    await t.pumpWidget(_inVak(ArtiestRondjes(namen: const ['Massive Attack', 'Tracey Thorn'], eerste: eerste)));
    await t.pump();
    eerste.requestFocus();
    await t.pump();
    expect(eerste.hasFocus, isTrue);
    expect(
        find.ancestor(of: find.byKey(const ValueKey('np-rondje-Massive Attack')), matching: find.byType(Focus)),
        findsWidgets);
  });

  group('bedrading (gelezen uit lib/main.dart)', () {
    final bron = File('lib/main.dart').readAsStringSync();

    test('Nu speelt zet de rondjes aan, met het eerste rondje als haak', () {
      // Naast elkaar en op de tv onder de titel; gestapeld staat de foto bovenaan, naast de kop (19-10-2026).
      expect(bron, contains('                  rondjes: !gestapeld,\n                  eersteRondje: gestapeld ? null : _eersteRondje,'));
    });

    test('op de hoes gaat OMHOOG naar het eerste rondje', () {
      final begin = bron.indexOf('KeyEventResult _pijlAlsNummerknop(');
      final lijf = bron.substring(begin, bron.indexOf('return _spoelPijlen.opToets(e);', begin));
      expect(lijf, contains('LogicalKeyboardKey.arrowUp'));
      expect(lijf, contains('_eersteRondje.requestFocus();'));
      expect(lijf.indexOf('if (!_opHoes)'), lessThan(lijf.indexOf('arrowUp')),
          reason: 'alleen vanaf de hoes — elders is omhoog gewoon tussen de knoppen lopen');
    });
  });
}
