/// De knoppen van "Genoeg" (Saber, 28-11-2026): de menuregel in de albummenu's en de knop op de artiestpagina.
/// Apart van kiezen_genoeg_test.dart: een widgettoets maakt van elke HttpClient in hetzelfde bestand een nep.
library;

import 'dart:io';

import 'package:debridmusic/main.dart' show genoegRegel;
import 'package:debridmusic/twijfel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('de knoppen', () {
    tearDown(() => genoegVanPc.value = const GenoegStand());

    testWidgets('de menuregel zegt wat hij doet, en draait om met de stand', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      expect(genoegRegel(ctx, artiest: 'Adele', album: '30').tekst, 'Genoeg — niet meer vragen');
      expect(genoegRegel(ctx, artiest: 'Adele').tekst, 'Genoeg — niet meer vragen');
      genoegVanPc.value = GenoegStand(platen: {genoegPlaat('Adele', '30')});
      expect(genoegRegel(ctx, artiest: 'Adele', album: '30').tekst, 'Weer vragen bij Kiezen');
      expect(genoegRegel(ctx, artiest: 'Adele', album: '25').tekst, 'Genoeg — niet meer vragen');
      expect(genoegRegel(ctx, artiest: 'Adele').tekst, 'Genoeg — niet meer vragen', reason: 'de plaat is de artiest niet');
    });

    test('in de drie albummenu\'s en op de artiestpagina, en de pagina\'s verversen wat de pc zegt', () {
      final m = _bron('lib/main.dart');
      final kop = m.indexOf('  ItemMenu _albumKopMenu() {');
      expect(m.substring(kop, m.indexOf('\n  }\n', kop)),
          contains('        [genoegRegel(context, artiest: album.artist, album: album.title)],'),
          reason: 'het menu van de albumpagina');
      expect(m, contains('        genoegRegel(context, artiest: a.artist, album: a.title),'), reason: 'een albumtegel');
      expect('[genoegRegel(context, artiest: album.artist, album: album.title)]'.allMatches(m), hasLength(2),
          reason: 'de albumpagina en Zoek hi-res');
      expect(m, contains("label: aan ? 'Weer vragen' : 'Genoeg',"));
      expect(m, contains('onPressed: () => zetGenoegOveral(context, artiest: widget.artist.name, aan: !aan),'));
      expect('unawaited(genoegVerversen(context.read<LibraryStore>()))'.allMatches(m), hasLength(2));
    });
  });
}
