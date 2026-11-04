// Ontdek op de pc als raster van hoezen (Saber, 18-10-2026: "tegels met hoezen"; 04-11-2026: "Tegels met ▶ en ⬇ op
// de tegel"). Op de gsm en de tv blijft het de lijst.
import 'dart:io';

import 'package:debridmusic/main.dart' show ontdekAlsRaster;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('raster op pc, Mac en iPad; lijst op gsm en tv', () {
    expect(ontdekAlsRaster(tv: false, smal: false), isTrue);
    expect(ontdekAlsRaster(tv: false, smal: true), isFalse, reason: 'gsm');
    expect(ontdekAlsRaster(tv: true, smal: false), isFalse, reason: 'tv');
  });

  test('de tegel: dezelfde als Albums, afspelen en downloaden op de hoes, de rest onder de rechtermuisknop', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final begin = main.indexOf('  Widget _tegel(int i, OntdekNummer n) {');
    expect(begin, greaterThan(0));
    final lijf = main.substring(begin, main.indexOf('\n  }\n', begin));
    expect(lijf, contains('builder: (context, haalt, _) => AlbumTegel('));
    expect(lijf, contains('onAfspelen: () => _speel(n),'));
    expect(lijf, contains('knop: _downloadControl(context, jobKey: sleutel, onDownload: () => _haal(n)'));
    expect(lijf, contains('onSecondaryTap: (bij) => _menu(n, bij: bij),'));
    expect(main, contains("MenuRegel(Icons.download_rounded, 'Downloaden (beste bron)', () => _haal(n)),"));
    expect(main, contains("MenuRegel(Icons.travel_explore_rounded, 'Bronnen zelf kiezen',"));
    expect(main, contains('else if (ontdekAlsRaster(tv: isTv, smal: isCompact(context)))'));
  });
}
