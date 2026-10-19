// Op de gsm stond de naam van de sectie in de balk én nog eens als kop op de pagina. Saber,
// 18-10-2026: "één keer de titel", als grote kop die inklapt (zoals Apple Music). De kop en het
// zoekveld staan nu in een NestedScrollView boven de pagina, en de titel verschijnt klein in de balk
// zodra de kop weg is.
import 'dart:io';

import 'package:debridmusic/ui/kop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // De aanname waar het op rust: een sectielijst zonder eigen scroller neemt op een telefoon de
  // scroller van de NestedScrollView over (`primary`), en dan klapt de kop eerst in. Een pagina met
  // een eigen ScrollController zou dat niet doen; die zijn er bij de secties niet.
  testWidgets('een lijst zonder eigen scroller laat de grote kop eerst inklappen', (t) async {
    final buiten = ScrollController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NestedScrollView(
          controller: buiten,
          headerSliverBuilder: (_, __) => [const SliverToBoxAdapter(child: GroteKop('Tracks'))],
          body: Column(children: [
            const Text('telling en knoppen'),
            Expanded(
              child: ListView.builder(
                itemCount: 100,
                itemBuilder: (_, i) => SizedBox(height: 50, child: Text('rij $i')),
              ),
            ),
          ]),
        ),
      ),
    ));
    expect(buiten.offset, 0);
    expect(find.text('Tracks'), findsOneWidget);
    await t.drag(find.text('rij 3'), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(buiten.offset, greaterThan(GroteKop.inklapGrens), reason: 'de kop klapt in terwijl de lijst schuift');
  });

  test('de schil: één titel, groot boven de pagina of klein in de balk', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main, contains('    return NestedScrollView(\n      controller: _gsmKop,'));
    expect(main, contains("SliverToBoxAdapter(child: GroteKop(titel, key: const ValueKey('gsm-grote-kop'))),"));
    expect(main, contains('if (_searchable) SliverToBoxAdapter(child: _searchBar(context)),'));
    expect(main, contains('final aan = _gsmKop.offset > GroteKop.inklapGrens;'));
    expect(main, contains('valueListenable: _titelInBalk,'));
    expect(main, contains('if (_gsmKop.hasClients) _gsmKop.jumpTo(0);'), reason: 'een nieuwe sectie begint met de kop');
    // De acht sectiepagina's met een eigen titel laten die op de gsm weg, Start zijn groet, en het
    // artiestenraster zijn kop zonder zoekopdracht.
    expect('if (!schilKop(context))'.allMatches(main).length, 10,
        reason: 'acht paginas, de schil zelf en de groet');
    expect(main, contains('if (!schilKop(context) || artists.length != widget.lib.artists.length)'),
        reason: 'artiestenraster');
    expect(main, contains('if (!ingebed && (title != null || !schilKop(context)))'), reason: 'albumraster');
    expect(main, contains("? '\${tracks.length} \${tracks.length == 1 ? 'nummer' : 'nummers'}'"));
    expect(main, contains("? '\${begroeting(DateTime.now())} 👋'"), reason: 'de groet is de grote kop op Start');
    expect(main, contains('bool schilKop(BuildContext context) => isCompact(context) && !isTv;'));
  });
}
