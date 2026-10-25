// "Scheiden per jaar" (Saber, 25-10-2026): Seal heeft twee albums die "Seal" heten (1991 en 1994), en in zijn bibliotheek
// stonden Killer (1991) en Kiss from a Rose (1994) samen op één tegel, in één map. Vanzelf op jaar splitsen mag niet: 26
// van zijn 892 albums hebben nummers met jaren die twee of meer uiteen liggen, en bijna allemaal is dat één plaat met
// rommelige jaartallen. Dus een knop, zoals "Uitgaves samenvoegen".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/dtos.dart';
import 'package:debridmusic/lan/ids.dart' show albumIdFor;
import 'package:debridmusic/organize.dart' show artistKey, normKey;
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';

String _sep(String p) => p.replaceAll('/', Platform.pathSeparator);

Track _t(String pad, String titel, int? jaar, {int nr = 0, String album = 'Seal', String artiest = 'Seal'}) =>
    Track(path: _sep(pad), title: titel, artist: artiest, album: album, trackNo: nr, year: jaar);

void main() {
  late Directory scratch;
  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_scheiden_');
    setAppDirForTest(scratch.path);
  });
  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  final seal = [
    _t('/m/Albums/Seal/Seal/04 - Killer.flac', 'Killer', 1991, nr: 4),
    _t('/m/Albums/Seal/Seal/06 - Kiss from a Rose.flac', 'Kiss from a Rose', 1994, nr: 6),
  ];

  LibraryStore maak(List<Track> ts) {
    final lib = LibraryStore()..configDirOverride = scratch.path;
    lib.tracks.addAll(ts);
    lib.rebuildAlbums();
    return lib;
  }

  test('zonder knop één plaat; na "Scheiden per jaar" twee, en dat blijft na een herstart', () async {
    final lib = maak(seal);
    expect(lib.albums.where((a) => a.title == 'Seal'), hasLength(1), reason: 'de nummers botsen niet: niets splitst vanzelf');
    final plaat = lib.albums.single;
    expect(lib.kanScheidenPerJaar(plaat), isTrue);
    await lib.scheidPerJaar(plaat);
    expect(lib.albums.map((a) => a.tracks.map((t) => t.title).join()).toSet(), {'Killer', 'Kiss from a Rose'});
    expect(lib.albums.every(lib.isGesplitst), isTrue);
    expect(lib.albums.any(lib.kanScheidenPerJaar), isFalse);

    final opnieuw = LibraryStore()..configDirOverride = scratch.path;
    await opnieuw.loadGesplitst();
    opnieuw.tracks.addAll(seal);
    opnieuw.rebuildAlbums();
    expect(opnieuw.albums, hasLength(2), reason: 'net als samenvoegen: de keuze staat op schijf');

    await opnieuw.herenigJaren(opnieuw.albums.first);
    expect(opnieuw.albums, hasLength(1));
    expect(opnieuw.isGesplitst(opnieuw.albums.single), isFalse);
  });

  test('alleen aangeboden met nummers uit minstens twee jaren, en niet bij een samengevoegde plaat', () async {
    final eenJaar = maak([seal.first, _t('/m/Albums/Seal/Seal/05 - Whirlpool.flac', 'Whirlpool', 1991, nr: 5)]);
    expect(eenJaar.kanScheidenPerJaar(eenJaar.albums.single), isFalse);
    final zonderJaar = maak([seal.first, _t('/m/Albums/Seal/Seal/07 - Wild.flac', 'Wild', null, nr: 7)]);
    expect(zonderJaar.kanScheidenPerJaar(zonderJaar.albums.single), isFalse);
    final samen = maak(seal);
    await samen.mergeEditions(samen.albums.single);
    expect(samen.kanScheidenPerJaar(samen.albums.single), isFalse);
  });

  test('scheiden haalt een samenvoeging weg, en samenvoegen een scheiding (de twee sluiten elkaar uit)', () async {
    final lib = maak(seal);
    await lib.mergeEditions(lib.albums.single);
    expect(lib.isMerged(lib.albums.single), isTrue);
    await lib.scheidPerJaar(lib.albums.single);
    expect(lib.albums, hasLength(2));
    expect(lib.albums.any(lib.isMerged), isFalse);
    await lib.mergeEditions(lib.albums.first);
    expect(lib.albums, hasLength(1));
    expect(lib.isGesplitst(lib.albums.single), isFalse);
  });

  test('gescheiden: elk jaar een eigen editie en dus een eigen id, en een eigen tracklijst', () async {
    final lib = maak(seal);
    await lib.scheidPerJaar(lib.albums.single);
    expect(lib.albums.map((a) => a.edition).toSet(), {'1991', '1994'});
    final ids = {for (final a in lib.albums) albumIdFor(artistKey(a.artist), normKey(a.title), a.edition)};
    expect(ids, hasLength(2), reason: 'met één id voegde een toestel ze weer samen');
    final killer = lib.albums.firstWhere((a) => a.edition == '1991');
    expect([for (final t in LibraryNormalise(lib).recordTracks(killer)) t.title], ['Killer'],
        reason: 'Kiss from a Rose is een andere plaat, geen persing van deze');
  });

  group('welke bestanden een eigen map krijgen', () {
    test('Seal: Killer blijft, Kiss from a Rose naar "Seal (1994)"', () {
      final plan = LibraryStore.planScheidingMappen(seal, 'Seal');
      expect(plan, hasLength(1));
      expect(plan.single.track.title, 'Kiss from a Rose');
      expect(plan.single.to, _sep('/m/Albums/Seal/Seal (1994)/06 - Kiss from a Rose.flac'));
    });

    test('het jaar met de meeste nummers blijft; nummers zonder jaar blijven; al gescheiden mappen niets', () {
      final pg = [
        _t('/m/PG/Peter Gabriel/01 - Moribund.flac', 'Moribund the Burgermeister', 1977, album: 'Peter Gabriel', artiest: 'Peter Gabriel'),
        _t('/m/PG/Peter Gabriel/02 - Solsbury.flac', 'Solsbury Hill', 1977, album: 'Peter Gabriel', artiest: 'Peter Gabriel'),
        _t('/m/PG/Peter Gabriel/03 - Intruder.flac', 'Intruder', 1980, album: 'Peter Gabriel', artiest: 'Peter Gabriel'),
        _t('/m/PG/Peter Gabriel/04 - Onbekend.flac', 'Onbekend', null, album: 'Peter Gabriel', artiest: 'Peter Gabriel'),
        _t('/m/PG/Peter Gabriel (1982)/01 - Rhythm.flac', 'The Rhythm of the Heat', 1982,
            album: 'Peter Gabriel', artiest: 'Peter Gabriel'),
      ];
      final plan = LibraryStore.planScheidingMappen(pg, 'Peter Gabriel');
      expect([for (final p in plan) p.track.title], ['Intruder']);
      expect(plan.single.to, _sep('/m/PG/Peter Gabriel (1980)/03 - Intruder.flac'));
    });
  });

  test('de stand reist mee naar de toestellen, en de pc kent de opdrachten', () {
    const dto = AlbumDto(id: 'a', artistId: 'b', artistName: 'Seal', title: 'Seal', gesplitst: true);
    expect(AlbumDto.fromJson(dto.toJson()).gesplitst, isTrue);
    expect(AlbumDto.fromJson(const AlbumDto(id: 'a', artistId: 'b', artistName: 'Seal', title: 'Seal').toJson()).gesplitst,
        isFalse);
    final server = File('lib/lan/server.dart').readAsStringSync();
    expect(server, contains("case 'splitYear':\n          await library.scheidPerJaar(album!);"));
    expect(server, contains("case 'unsplitYear':\n          await library.herenigJaren(album!);"));
    final catalog = File('lib/lan/catalog.dart').readAsStringSync();
    expect(catalog, contains('gesplitst: library.isGesplitst(album),'));
    expect(catalog, contains("..add(a.gesplitst ? 'j' : '')"), reason: 'anders krijgt een toestel een 304 en de oude knop');
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains("key: const ValueKey('scheiden-per-jaar'),"));
    expect(main, contains('await library.loadGesplitst();'));
  });
}
