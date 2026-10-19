// Ontdek op de pc als raster van hoezen (Saber, 18-10-2026: "tegels met hoezen"). Op de gsm en de tv
// blijft het de lijst.
import 'dart:io';

import 'package:debridmusic/main.dart' show ontdekAlsRaster;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('raster op pc, Mac en iPad; lijst op gsm en tv', () {
    expect(ontdekAlsRaster(tv: false, smal: false), isTrue);
    expect(ontdekAlsRaster(tv: false, smal: true), isFalse, reason: 'gsm');
    expect(ontdekAlsRaster(tv: true, smal: false), isFalse, reason: 'tv');
  });

  test('de tegel: dezelfde als Albums, afspelen op de hoes, de rest onder de rechtermuisknop', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final begin = main.indexOf('  Widget _tegel(int i, RecTrack t) {');
    expect(begin, greaterThan(0));
    final lijf = main.substring(begin, main.indexOf('\n  }\n', begin));
    expect(lijf, contains('return AlbumTegel('));
    expect(lijf, contains('onAfspelen: () => _play(i, t),'));
    expect(lijf, contains('onSecondaryTap: (bij) => _menu(i, t, bij: bij),'));
    expect(main, contains("MenuRegel(Icons.download_rounded, 'Bronnen / download', () => _bronnen(t)),"));
    expect(main, contains('gridDelegate: tegelRaster(context, c.crossAxisExtent, extra: 2),'));
    expect(main, contains('else if (ontdekAlsRaster(tv: isTv, smal: isCompact(context)))'));
  });
}
