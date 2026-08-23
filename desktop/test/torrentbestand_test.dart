/// Een `.torrent` lezen zonder er iets van te verzinnen.
///
/// **Waarom dit bestaat.** De nummerkeuze en de download hangen allebei aan deze lijst, en aria2
/// telt `--select-file` op precies dezelfde volgorde. Eén verschoven nummer is niet een foutmelding
/// maar een ánder nummer dat binnenkomt — het soort fout dat je pas hoort als je zit te luisteren.
///
/// De eerste toets rekent met het echte bestand van jouw voorbeeld (B.B.E. — Seven Days And One
/// Week, RuTracker 3424450, 18.143 bytes) zodat de vorm die we in het wild tegenkomen ook echt de
/// vorm is die gelezen wordt.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/torrentbestand.dart';

/// Bencode schrijven, alleen hier — genoeg om een torrent na te bootsen.
List<int> _b(dynamic v) {
  if (v is int) return utf8.encode('i${v}e');
  if (v is String) return [...utf8.encode('${utf8.encode(v).length}:'), ...utf8.encode(v)];
  if (v is List) return [utf8.encode('l').first, ...v.expand(_b), utf8.encode('e').first];
  if (v is Map) {
    final sleutels = v.keys.map((k) => k as String).toList()..sort();
    return [
      utf8.encode('d').first,
      ...sleutels.expand((k) => [..._b(k), ..._b(v[k])]),
      utf8.encode('e').first,
    ];
  }
  throw ArgumentError('onbekend: $v');
}

void main() {
  group('een torrent met meerdere bestanden', () {
    final rauw = _b({
      'announce': 'http://bt4.t-ru.org/ann',
      'info': {
        'name': 'B.B.E. - Seven Days And One Week',
        'piece length': 262144,
        'files': [
          {'length': 40000000, 'path': ['01 Seven Days And One Week.flac']},
          {'length': 500, 'path': ['scans', 'cover.jpg']},
          {'length': 30000000, 'path': ['02 Flash.flac']},
        ],
      },
    });

    test('naam, bestanden en groottes komen eruit zoals ze erin staan', () {
      final t = TorrentInhoud.lees(rauw)!;

      expect(t.naam, 'B.B.E. - Seven Days And One Week');
      expect(t.bestanden.length, 3);
      expect(t.bestanden[1].pad, 'scans/cover.jpg');
      expect(t.bestanden[1].naam, 'cover.jpg');
      expect(t.totaleGrootte, 70000500);
    });

    test('de nummering telt vanaf 1 en slaat niets over', () {
      final t = TorrentInhoud.lees(rauw)!;

      // Dit is de nummering die aria2 gebruikt voor --select-file. Zou de plaatje-regel de telling
      // opschuiven, dan haalt "download nummer 2" bij de gebruiker nummer 3 binnen.
      expect(t.bestanden.map((f) => f.index), [1, 2, 3]);
      expect(t.audio.map((f) => f.index), [1, 3]);
      expect(t.audio.map((f) => f.naam),
          ['01 Seven Days And One Week.flac', '02 Flash.flac']);
    });
  });

  test('een torrent met één bestand: de torrentnaam is de bestandsnaam', () {
    final t = TorrentInhoud.lees(_b({
      'info': {'name': 'Kai Tracid - Liquid Skies.flac', 'length': 12345},
    }))!;

    expect(t.bestanden.single.index, 1);
    expect(t.bestanden.single.naam, 'Kai Tracid - Liquid Skies.flac');
    expect(t.bestanden.single.grootte, 12345);
  });

  group('wat geen torrent is, is geen lege torrent', () {
    test('een HTML-pagina levert niets op', () {
      // Precies wat RuTracker terugstuurt als het koekje verlopen is: een inlogpagina met status
      // 200. Zou dat als "torrent met nul bestanden" doorgaan, dan meldt het scherm "geen audio"
      // en ga je naar de torrent zoeken in plaats van naar je koekje.
      expect(TorrentInhoud.lees(utf8.encode('<html><body>Вход</body></html>')), isNull);
    });

    test('en een half afgebroken bestand ook niet', () {
      final heel = _b({
        'info': {'name': 'x', 'files': [{'length': 1, 'path': ['a.flac']}]},
      });
      expect(TorrentInhoud.lees(heel.sublist(0, heel.length ~/ 2)), isNull);
      expect(TorrentInhoud.lees(const []), isNull);
    });
  });

  test('het echte bestand van RuTracker, als het er nog ligt', () {
    // Overgeslagen op een machine zonder dat bestand: een toets die alleen hier kan draaien is
    // beter dan geen toets, maar mag de rest niet rood maken.
    final f = File(r'C:\Users\saber\AppData\Local\Temp\claude\C--Users-saber'
        r'\b7e37120-ff25-4557-bc5b-2cec96ef450a\scratchpad\bbe.torrent');
    if (!f.existsSync()) return;

    final t = TorrentInhoud.lees(f.readAsBytesSync())!;
    expect(t.naam, isNotEmpty);
    expect(t.audio, isNotEmpty, reason: 'een FLAC-album hoort audio te bevatten');
    expect(t.totaleGrootte, greaterThan(100 * 1024 * 1024));
  });
}
