/// Het getal met lopende downloads in de balk bovenaan (gsm) brengt je naar Mijn downloads (20-11-2026).
///
/// Saber, met een schermafdruk van Online zoeken en een "1" naast het tandwiel: *"als ik klik op de download aantal
/// button dat ik naar de downloads gaan"*.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('DE KERN: een tik op het getal gaat naar Mijn downloads (sectie 6)', () {
    final m = _bron('lib/main.dart');
    expect(m, contains('            _DownloadBadge(marge: const EdgeInsets.only(right: 4), opTik: () => gaNaarSectie?.call(6)),'));
    expect(m, contains("    (6, 'Mijn downloads', Icons.download_rounded),"), reason: 'sectie 6 is Mijn downloads');
  });

  test('met een ruim raakvlak en een uitleg bij lang drukken; in de la blijft het een getal', () {
    final m = _bron('lib/main.dart');
    expect(m, contains("      message: 'Naar Mijn downloads',"));
    expect(m, contains('        onTap: tik,'));
    expect(m, contains('        marge = EdgeInsets.zero,\n        opTik = null;'), reason: 'de la: alleen het getal');
  });
}
