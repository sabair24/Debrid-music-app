/// Verzamelingen: de naam en de koppelingen in de gedeelde staat, en verhuizen op de pc (21-11-2026).
///
/// Saber koos: een eigen map op de pc, en een nummer mag ook in meer dan één verzameling (als verwijzing). Verhuizen
/// gaat nooit met een kopie: een bestand dat openstaat, blijft staan — anders stonden er twee bestanden met één id.
library;

import 'dart:io';

import 'package:debridmusic/favorieten.dart';
import 'package:debridmusic/lan/ids.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/organize.dart' show artistKey, normKey;
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/verzamelingen.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late Directory map;
  final sep = Platform.pathSeparator;
  // Echte tijden: een grafsteen ouder dan dertig dagen ruimt de staat meteen op (_pruneTombstones).
  final t0 = DateTime.now().millisecondsSinceEpoch;
  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_verzameling_');
    setAppDirForTest(map.path);
  });
  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  LanStateStore staat() => LanStateStore(File('${map.path}${sep}state.json'));

  group('de gedeelde staat', () {
    test('DE KERN: maken, koppelen (één keer), ontkoppelen, hernoemen en weggooien', () {
      final s = staat();
      s.applyOps([
        {'type': 'verzameling.maak', 'naam': 'Vocal jazz', 'at': t0 + 1},
        {'type': 'verzameling.koppel', 'naam': 'vocal jazz', 'ids': ['a', 'b', 'a'], 'at': t0 + 2},
      ]);
      expect(s.verzamelingen['vocal jazz']!.koppelingen, ['a', 'b'], reason: 'een verwijzing staat er één keer in');
      expect(s.verzamelingen['vocal jazz']!.naam, 'Vocal jazz');
      s.applyOps([
        {'type': 'verzameling.ontkoppel', 'naam': 'Vocal jazz', 'ids': ['a'], 'at': t0 + 3},
        {'type': 'verzameling.hernoem', 'van': 'Vocal jazz', 'naar': 'Jazz vocals', 'at': t0 + 4},
      ]);
      expect(s.verzamelingen.keys, ['jazz vocals']);
      expect(s.verzamelingen['jazz vocals']!.koppelingen, ['b']);
      s.applyOps([
        {'type': 'verzameling.weg', 'naam': 'Jazz vocals', 'at': t0 + 5},
      ]);
      expect(s.verzamelingen['jazz vocals']!.deleted, isTrue, reason: 'een grafsteen, zodat een toestel het hoort');
      s.applyOps([
        {'type': 'verzameling.maak', 'naam': 'Jazz vocals', 'at': t0 + 6},
      ]);
      expect(s.verzamelingen['jazz vocals']!.deleted, isFalse, reason: 'terughalen mag');
    });

    test('een oudere bewerking wint niet, en alles gaat mee naar schijf en naar de toestellen', () {
      final s = staat();
      s.applyOps([
        {'type': 'verzameling.koppel', 'naam': 'Soul classics', 'ids': ['x'], 'at': t0 + 10},
        {'type': 'verzameling.weg', 'naam': 'Soul classics', 'at': t0 + 5},
      ]);
      expect(s.verzamelingen['soul classics']!.deleted, isFalse, reason: 'een weggooien van vóór de koppeling telt niet');
      expect(s.snapshot()['verzamelingen'], [
        {'naam': 'Soul classics', 'koppelingen': ['x'], 'updatedAt': t0 + 10},
      ]);
      expect(staat().snapshot().containsKey('verzamelingen'), isFalse,
          reason: 'zonder verzamelingen blijft de staat wat hij was');
      final v = VerzamelingInfo.fromJson({'naam': 'Soul classics', 'koppelingen': ['x'], 'updatedAt': 10});
      expect(v.sleutel, 'soul classics');
      expect(v.koppelingen, ['x']);
    });

    test('de winkel: op de pc rechtstreeks, op een toestel uit wat de pc stuurde', () async {
      final s = staat();
      final pc = Verzamelingen()..winkel = s;
      await pc.maak('Vocal jazz');
      await pc.koppel('Vocal jazz', ['t1']);
      await pc.maak('Crooners & standards');
      expect(pc.namen, ['Crooners & standards', 'Vocal jazz']);
      expect(pc.koppelingenVan('vocal jazz'), ['t1']);
      expect(pc.waarGekoppeld('t1'), ['Vocal jazz']);
      await pc.weg('Crooners & standards');
      expect(pc.namen, ['Vocal jazz']);

      final toestel = Verzamelingen()..vanServer(s.snapshot()['verzamelingen'] as List);
      expect(toestel.gehoord, isTrue);
      expect(toestel.namen, ['Vocal jazz']);
      expect(toestel.koppelingenVan('Vocal jazz'), ['t1']);
    });
  });

  group('verhuizen op de pc', () {
    late String wortel;
    late File nummer, hoes;
    setUp(() {
      wortel = '${map.path}${sep}muziek';
      final dir = Directory('$wortel${sep}DebridMusic Downloads${sep}Singles${sep}Billie Holiday')
        ..createSync(recursive: true);
      nummer = File('${dir.path}${sep}My Man.flac')..writeAsBytesSync(List.filled(4096, 1));
      hoes = File('${dir.path}${sep}cover.jpg')..writeAsBytesSync([1, 2, 3]);
    });

    LibraryStore bibliotheek() => LibraryStore()
      ..rootPath = wortel
      ..configDirOverride = map.path;

    test('DE KERN: naar de verzameling met het oude pad erin; de hoes gaat mee en de lege map verdwijnt', () async {
      final lib = bibliotheek();
      final r = await lib.naarVerzameling([nummer.path], 'Vocal jazz');
      expect(r.verhuisd, 1);
      expect(r.bezet, 0);
      final nieuw = File('$wortel${sep}DebridMusic Downloads${sep}Verzamelingen${sep}Vocal jazz${sep}Singles'
          '${sep}Billie Holiday${sep}My Man.flac');
      expect(nieuw.existsSync(), isTrue);
      expect(nummer.existsSync(), isFalse, reason: 'verhuisd, niet gekopieerd');
      expect(File('${nieuw.parent.path}${sep}cover.jpg').existsSync(), isTrue, reason: 'de hoes gaat mee');
      expect(hoes.parent.existsSync(), isFalse, reason: 'de leeggelopen map verdwijnt');
      expect(trackIdFor(nieuw.path, wortel), trackIdFor(nummer.path, wortel), reason: 'hetzelfde id');

      final terug = await lib.naarVerzameling([nieuw.path], null);
      expect(terug.verhuisd, 1);
      expect(nummer.existsSync(), isTrue, reason: 'terug naar waar het stond');
    });

    test('nooit overschrijven: staat er al iets op de plek, dan blijft alles staan', () async {
      final doel = File('$wortel${sep}DebridMusic Downloads${sep}Verzamelingen${sep}Vocal jazz${sep}Singles'
          '${sep}Billie Holiday${sep}My Man.flac')
        ..createSync(recursive: true)
        ..writeAsStringSync('ander');
      final r = await bibliotheek().naarVerzameling([nummer.path], 'Vocal jazz');
      expect(r.verhuisd, 0);
      expect(r.bezet, 1);
      expect(nummer.existsSync(), isTrue);
      expect(doel.readAsStringSync(), 'ander');
    });

    test('een naam die als map kan: "AC/DC" verhuist naar "AC-DC"', () async {
      await bibliotheek().naarVerzameling([nummer.path], 'AC/DC');
      expect(
          Directory('$wortel${sep}DebridMusic Downloads${sep}Verzamelingen${sep}AC-DC').existsSync(), isTrue);
    });
  });

  group('het hartje gaat mee', () {
    test('DE KERN: een favoriete plaat die naar een verzameling verhuisde, houdt zijn hartje', () {
      final s = staat();
      final fav = Favorieten()..winkel = s;
      final oud = albumIdFor(artistKey('Billie Holiday'), normKey('Lady in Satin'), null);
      s.applyOps([
        {'type': 'favorite', 'kind': 'album', 'id': oud, 'on': true, 'at': t0 + 1},
      ]);
      final lib = LibraryStore()
        ..tracks.add(Track(
            path: r'D:\m\DebridMusic Downloads\Verzamelingen\Vocal jazz\Albums\Billie Holiday\Lady in Satin\01.flac',
            title: "I'm a Fool to Want You",
            artist: 'Billie Holiday',
            album: 'Lady in Satin',
            trackNo: 1))
        ..rebuildAlbums();
      expect(fav.volgTegels(lib.albums), 1);
      final nieuw = albumIdFor(artistKey('Billie Holiday'), normKey('Lady in Satin'), null, verzameling: 'Vocal jazz');
      expect(s.favoriteAlbums, {nieuw});
    });

    test('en terug: de plaat uit de verzameling krijgt het hartje van zijn plek daar', () {
      final s = staat();
      final fav = Favorieten()..winkel = s;
      final inVerz = albumIdFor(artistKey('Dean Martin'), normKey('This Time'), null, verzameling: 'Crooners & standards');
      s.applyOps([
        {'type': 'favorite', 'kind': 'album', 'id': inVerz, 'on': true, 'at': t0 + 1},
      ]);
      final lib = LibraryStore()
        ..tracks.add(Track(path: r'D:\m\Albums\Dean Martin\This Time\01.flac', title: 'x', artist: 'Dean Martin', album: 'This Time', trackNo: 1))
        ..rebuildAlbums();
      expect(fav.volgTegels(lib.albums, verzamelingNamen: const ['Crooners & standards']), 1);
      expect(s.favoriteAlbums, {albumIdFor(artistKey('Dean Martin'), normKey('This Time'), null)});
    });
  });

  group('aangesloten (gelezen uit de bron)', () {
    test('een toestel vraagt het de pc; de server verhuist en maakt de naam aan', () {
      final l = _bron('lib/library.dart');
      expect(l, contains("      await _editOnPc({'op': 'naarVerzameling', 'trackIds': ids, if (doelNaam != null) 'naam': doelNaam});"));
      expect(l, contains('        final at = await verplaatsZonderKopie(File(p), doel);'), reason: 'nooit kopiëren');
      final s = _bron('lib/lan/server.dart');
      expect(s, contains("        case 'naarVerzameling':"));
      expect(s, contains("    if (op != 'removeTracks' &&\n        op != 'naarVerzameling' &&"));
      expect(s, contains("          if (naam.isNotEmpty) state.applyOps([{'type': 'verzameling.maak', 'naam': verzamelMapnaam(naam)}]);"));
    });

    test('de winkel staat op elk toestel, en het hartje kent de namen', () {
      final m = _bron('lib/main.dart');
      expect(m, contains('  if (mode.owner) verzamelingen.winkel = sharing.state;'));
      expect(m, contains("          verzamelingen.vanServer((s['verzamelingen'] as List? ?? const []));"));
      expect(m, contains('      verzamelingen.duwOps = duw;'));
      expect(m, contains('        verzamelingNamen: {...library.verzamelingNamen, ...verzamelingen.namen}));'));
    });
  });
}
