// "Klinkt als" tot vijftig en "Recent toegevoegd" tot vijftig met "Alles" (Saber, 26-10-2026: "recente toegevoegd meer
// wordt aangevuld tot 50 liedjes, plus een button naar allemaal. klinkt als moet ook meer gevuld worden, tot zeker 50
// artiesten"). Deezer geeft hoogstens twintig verwanten; gemeten met Last.fm erbij: Destiny's Child, Steps en Khaled
// alle drie 50.
import 'dart:io';

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/klinkt_als.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogArtist _a(String naam, [int id = 0]) => CatalogArtist(id == 0 ? naam.hashCode : id, naam, null, 1);

List<CatalogArtist> _deezer(int n) => [for (var i = 0; i < n; i++) _a('Deezer $i', i + 1)];

List<({String naam, double maat})> _lastfm(int n, {double van = 1}) =>
    [for (var i = 0; i < n; i++) (naam: 'Lastfm $i', maat: van - i / 1000)];

Future<List<CatalogArtist>> _exact(String naam) async => [_a(naam)];

void main() {
  test('DE KERN: de twintig van Deezer vooraan, Last.fm vult aan tot vijftig', () async {
    final uit = await klinktAlsAanvullen(
      artiest: "Destiny's Child",
      deezer: _deezer(20),
      lastfm: () async => [
        (naam: "Destiny's Child", maat: 1.0), // de artiest zelf
        (naam: 'Deezer 3', maat: .99), // staat er al
        ..._lastfm(60, van: .9),
      ],
      zoekArtiest: _exact,
      verwanten: (_) async => throw 'niet nodig',
    );
    expect(uit, hasLength(kKlinktAlsDoel));
    expect([for (final a in uit.take(20)) a.name], [for (final a in _deezer(20)) a.name]);
    expect(uit[20].name, 'Lastfm 0', reason: 'op maat');
    expect({for (final a in uit) a.name}, hasLength(uit.length), reason: 'niemand twee keer');
    expect(uit.any((a) => a.name == "Destiny's Child"), isFalse);
  });

  test('een naamgenoot bij Deezer telt niet: alleen exact dezelfde naam', () async {
    final uit = await klinktAlsAanvullen(
      artiest: 'Khaled',
      deezer: _deezer(20),
      lastfm: () async => [(naam: 'Cheb Mami', maat: .9), (naam: 'Faudel', maat: .8)],
      zoekArtiest: (n) async => n == 'Cheb Mami' ? [_a('Cheb Mami Junior')] : [_a(n)],
      verwanten: (_) async => const [],
    );
    expect(uit.map((a) => a.name), isNot(contains('Cheb Mami Junior')));
    expect(uit.last.name, 'Faudel');
  });

  test('zonder Last.fm: de verwanten van de verwanten, wie het vaakst terugkomt eerst', () async {
    final deezer = _deezer(20);
    final uit = await klinktAlsAanvullen(
      artiest: 'Steps',
      deezer: deezer,
      zoekArtiest: (_) async => throw 'niet nodig',
      verwanten: (id) async => [
        _a('Steps'),
        deezer[5],
        _a('Vaak'),
        if (id <= 3) _a('Drie keer'),
        _a('Van $id'),
      ],
    );
    expect(uit.length, 20 + 2 + kKlinktAlsTweedeKring);
    expect(uit[20].name, 'Vaak', reason: 'vijf keer');
    expect(uit[21].name, 'Drie keer');
    expect(uit.where((a) => a.name == deezer[5].name), hasLength(1));
    expect(uit.any((a) => a.name == 'Steps'), isFalse);
  });

  test('Last.fm faalt of geeft te weinig: de tweede kring vult de rest', () async {
    final uit = await klinktAlsAanvullen(
      artiest: 'X',
      deezer: _deezer(20),
      lastfm: () async => throw 'geen netwerk',
      zoekArtiest: _exact,
      verwanten: (id) async => [for (var i = 0; i < 10; i++) _a('Kring $id-$i')],
    );
    expect(uit, hasLength(kKlinktAlsDoel));
  });

  test('Deezer kent niemand: Last.fm vult de rij alleen; en de rij groeit tussendoor', () async {
    final standen = <int>[];
    final uit = await klinktAlsAanvullen(
      artiest: 'Steps',
      deezer: const [],
      lastfm: () async => _lastfm(80),
      zoekArtiest: _exact,
      verwanten: (_) async => throw 'niet nodig',
      tussendoor: (l) => standen.add(l.length),
    );
    expect(uit, hasLength(kKlinktAlsDoel));
    expect(standen.first, kKlinktAlsTegelijk);
    expect(standen, orderedEquals([...standen]..sort()));
  });

  test('aangesloten: artiestpagina, Start met vijftig en "Alles" naar Albums op Recent toegevoegd', () {
    final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(m, contains('      await klinktAlsAanvullen(\n        artiest: naam,\n        deezer: r,\n'));
    expect(m, contains("lastfm: sleutel.isEmpty ? null : () => _lastfmBron.verwanteArtiesten(naam, sleutel: sleutel, limit: 100),"));
    expect(m, contains('const int kRecentOpStart = 50;'));
    expect(m, contains("_localRow(recent.take(kRecentOpStart).toList(), rij: 'recent')"));
    expect(m, contains("_AllesKnop(key: const ValueKey('recent-alles'), aantal: recent.length, onPressed: naarRecentToegevoegd)"));
    expect(m, contains('  void _naarRecentToegevoegd() {\n    setState(() => _sort = AlbumSort.toegevoegd);\n    _gaNaar(0);\n  }'));
    expect(m, contains('    naarRecentToegevoegd = _naarRecentToegevoegd;\n'));
    expect(kKlinktAlsDoel, 50);
  });
}
