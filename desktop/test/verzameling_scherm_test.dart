/// Verzamelingen op het scherm: een eigen menu-item, een rij op Start, een tab boven je bibliotheek, en "Naar
/// verzameling…" in het menu van een nummer of plaat (Saber, 21-11-2026: alle drie de plekken).
library;

import 'dart:io';

import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart' show NavSections, alleVerzamelingNamen, nummersVanVerzameling;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/ui/menu_iconen.dart';
import 'package:debridmusic/verzamelingen.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

/// Een bibliotheek met vaste id's (zoals een toestel ze uit het stroomadres haalt).
class _Lib extends LibraryStore {
  @override
  String? gedeeldId(String path) => 'id:${path.split(r'\').last}';
}

void main() {
  test('DE KERN: de namen uit de mappen én de lege uit de staat; de nummers uit de map én de verwijzingen', () async {
    final lib = _Lib()
      ..tracks.addAll([
        Track(path: r'D:\m\DebridMusic Downloads\Verzamelingen\Vocal jazz\Singles\a.flac', title: 'A', artist: 'X', album: ''),
        Track(path: r'D:\m\DebridMusic Downloads\Singles\b.flac', title: 'B', artist: 'Y', album: ''),
      ])
      ..rebuildAlbums();
    final verz = Verzamelingen()..winkel = LanStateStore(File('${Directory.systemTemp.createTempSync('dm_vs_').path}${Platform.pathSeparator}s.json'));
    await verz.maak('Crooners & standards');
    await verz.koppel('Vocal jazz', ['id:b.flac']);
    expect(alleVerzamelingNamen(lib, verz), ['Crooners & standards', 'Vocal jazz']);
    expect([for (final t in nummersVanVerzameling(lib, verz, 'vocal jazz')) t.title], ['A', 'B'],
        reason: 'B staat er als verwijzing in, en blijft ook in je bibliotheek');
    expect(lib.mixTracks.map((t) => t.title), ['B']);
    expect(nummersVanVerzameling(lib, verz, 'Crooners & standards'), isEmpty);
  });

  test('een eigen menu-item met een eigen icoon, na Artiesten', () {
    final ids = [for (final (id, _, _) in NavSections.items) id];
    expect(ids.indexOf(11), ids.indexOf(1) + 1);
    expect(NavSections.items.firstWhere((s) => s.$1 == 11).$2, 'Verzamelingen');
    expect(menuIcoonVoorSectie(11), MenuIcoonSoort.verzamelingen);
    expect(NavSections.voorTv.map((s) => s.$1), contains(11), reason: 'ook op de tv');
  });

  test('aangesloten: de sectie, de tab, de rij op Start en het menu', () {
    final m = _bron('lib/main.dart');
    expect(m, contains('    if (_view == 11) return const VerzamelingenView();'));
    expect(m, contains('  bool get _bibSectie => _view == 0 || _view == 1 || _view == 4 || _view == 11;'));
    expect(m, contains('      return _bibSectie ? Column(children: [_bibTabs(), Expanded(child: wissel)]) : wissel;'));
    expect(m, contains('        if (_bibSectie) SliverToBoxAdapter(child: _bibTabs()),'));
    expect(m, contains('    if (id == 0 || id == 1 || id == 4) _laatsteBib = id;'));
    expect(m, contains("              'Verzamelingen',\n              ListView.separated("));
    expect(m, contains('                  onPressed: () => gaNaarSectie?.call(11))),'));
    expect(m, contains('      _verzamelingRegels(context, [t]),'));
    expect(m, contains('      _verzamelingRegels(context, nummers),'));
  });
}
