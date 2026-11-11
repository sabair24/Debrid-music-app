import 'dart:async';
import 'dart:io';

import 'package:debridmusic/per_nummer_zoeker.dart';
import 'package:flutter_test/flutter_test.dart';

/// Saber, 09-11-2026: het getal naast een nummer op een albumpagina was te laag (Doo Wop 53, bij het downloaden 226). Hij koos:
/// per nummer, op de achtergrond.
void main() {
  group('per nummer zoeken', () {
    test('elk nummer één keer, in volgorde, en niet wat je al hebt', () async {
      final gezocht = <int>[];
      await zoekPerNummer<int>([1, 2, 3, 4, 5], nodig: (n) => n != 3, nogNodig: () => true, zoek: (n) async => gezocht.add(n));
      expect(gezocht, [1, 2, 4, 5]);
    });

    test('hoogstens drie tegelijk', () async {
      var nu = 0, hoogste = 0;
      await zoekPerNummer<int>(List.generate(10, (i) => i), nodig: (_) => true, nogNodig: () => true, zoek: (_) async {
        nu++;
        if (nu > hoogste) hoogste = nu;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        nu--;
      });
      expect(hoogste, kPerNummerTegelijk);
    });

    test('ga je weg, dan gaat er niets meer uit', () async {
      var open = true;
      final gezocht = <int>[];
      await zoekPerNummer<int>(List.generate(20, (i) => i), nodig: (_) => true, nogNodig: () => open, zoek: (n) async {
        gezocht.add(n);
        open = false;
      });
      expect(gezocht.length, lessThanOrEqualTo(kPerNummerTegelijk));
    });

    test('een fout bij één nummer laat de rest doorgaan', () async {
      final gezocht = <int>[];
      await zoekPerNummer<int>([1, 2, 3], nodig: (_) => true, nogNodig: () => true, tegelijk: 1, zoek: (n) async {
        if (n == 1) throw Exception('Soulseek zwijgt');
        gezocht.add(n);
      });
      expect(gezocht, [2, 3]);
    });

    test('een box van honderd nummers: niet allemaal', () async {
      var aantal = 0;
      await zoekPerNummer<int>(List.generate(100, (i) => i), nodig: (_) => true, nogNodig: () => true, zoek: (_) async => aantal++);
      expect(aantal, kPerNummerMax);
    });
  });

  group('samenvoegen', () {
    test('de albumvraag blijft vooraan, en dezelfde kopie telt één keer', () {
      expect(samenPerNummer(['a', 'b'], ['b', 'c'], (s) => s), ['a', 'b', 'c']);
    });

    test('nog geen vraag per nummer: de lijst van het album', () {
      final album = ['a'];
      expect(identical(samenPerNummer(album, null, (s) => s), album), isTrue);
      expect(identical(samenPerNummer(album, const [], (s) => s), album), isTrue);
    });
  });

  group('de bedrading op de albumpagina', () {
    final bron = File('lib/main.dart').readAsStringSync();
    final begin = bron.indexOf('class _AlbumBrowsePageState');
    final pagina = bron.substring(begin, bron.indexOf('\nclass ', begin + 10));

    test('het begint als de nummers vaststaan en de albumvraag klaar is', () {
      expect(pagina, contains('if (_perNummerGestart || !_tracksKlaar || _slskBusy || !mounted || _tracks.isEmpty) return;'));
      expect(pagina, contains('_tracksKlaar = true;'));
      expect(RegExp(r'_zorgVoorPerNummer\(\);').allMatches(pagina).length, 2, reason: 'na het laden en na de albumvraag');
    });

    test('als telling en zonder extra varianten, zodat een album niet het dubbele kost', () {
      final lijf = pagina.substring(pagina.indexOf('Future<void> _zoekPerNummer()'));
      expect(lijf, contains('telling: true,'), reason: 'het laagste werk van de app, niet gewoon achtergrond');
      expect(lijf, contains('terugval: false,'));
      expect(lijf, contains('nogNodig: () => mounted'));
      expect(lijf, contains('nodig: (t) => _owned(t) == null,'), reason: 'wat je al hebt, kost geen vraag');
      expect(lijf, contains('zeefKandidaten('), reason: 'dezelfde zeef als de telling');
    });

    test('het getal en de download gebruiken het samen met de albumvraag', () {
      expect(pagina, contains('samenPerNummer(_slskPerTitel[sleutel] ?? const [], _perNummer[sleutel],'));
    });
  });
}
