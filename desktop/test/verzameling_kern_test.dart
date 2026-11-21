/// Verzamelingen: de kern — de map, het id dat een verhuizing overleeft, en "vindbaar, niet gemengd" (21-11-2026).
///
/// Saber, na een radio vanaf Nancy Wilson: *"die zouden eigenlijk in een aparte afspeelijst kunnen in plaats van in men
/// bibliotheek tussen men andere liedjes"*. Gekozen: een tweede bibliotheek met een eigen map, vindbaar maar niet gemengd
/// met je gewone muziek, en een eigen smaak per verzameling.
library;

import 'dart:io';

import 'package:debridmusic/lan/dtos.dart';
import 'package:debridmusic/lan/ids.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart' show radioEigen;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/verzameling.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

Track _t(String pad, {String artiest = 'Billie Holiday', String album = 'Lady in Satin', String titel = 'Song'}) =>
    Track(path: pad, title: titel, artist: artiest, album: album, trackNo: 1, isFlac: true);

void main() {
  group('de map', () {
    test('DE KERN: een bestand uit de downloadmap houdt zijn pad, onder Verzamelingen\\<naam>', () {
      const oud = 'DebridMusic Downloads/Singles/Billie Holiday/My Man.flac';
      final nieuw = relInVerzameling(oud, 'Vocal jazz');
      expect(nieuw, 'DebridMusic Downloads/Verzamelingen/Vocal jazz/Singles/Billie Holiday/My Man.flac');
      expect(verzamelingUitRel(nieuw), 'Vocal jazz');
      expect(relZonderVerzameling(nieuw), oud);
    });

    test('van buiten de downloadmap: met het volle oude pad onder _buiten', () {
      const oud = 'Ella Fitzgerald/Ella and Louis/01 Can\'t We Be Friends.flac';
      final nieuw = relInVerzameling(oud, 'Vocal jazz');
      expect(nieuw, 'DebridMusic Downloads/Verzamelingen/Vocal jazz/_buiten/$oud');
      expect(relZonderVerzameling(nieuw), oud);
    });

    test('van de ene verzameling naar de andere, en een gewoon bestand heeft er geen', () {
      final inVocal = relInVerzameling('DebridMusic Downloads/Singles/Dean Martin/Sway.flac', 'Vocal jazz');
      expect(relInVerzameling(inVocal, 'Crooners & standards'),
          'DebridMusic Downloads/Verzamelingen/Crooners & standards/Singles/Dean Martin/Sway.flac');
      expect(verzamelingUitRel('DebridMusic Downloads/Singles/Dean Martin/Sway.flac'), isNull);
      expect(verzamelingUitRel('DebridMusic Downloads/Verzamelingen/Leeg'), isNull, reason: 'een map is geen bestand');
      expect(relZonderVerzameling('Albums/X/y.flac'), 'Albums/X/y.flac');
    });

    test('op het pad van de pc, zonder de wortel te kennen; een stroomadres heeft er geen', () {
      expect(verzamelingUitPad(r'D:\Flac music 2024\DebridMusic Downloads\Verzamelingen\Soul classics\Singles\a.flac'),
          'Soul classics');
      expect(verzamelingUitPad(r'D:\Flac music 2024\DebridMusic Downloads\Singles\a.flac'), isNull);
      expect(verzamelingUitPad('http://pc.invalid/stream/abc.flac'), isNull);
    });

    test('een naam die als map kan', () {
      expect(verzamelMapnaam('AC/DC & co.'), 'AC-DC & co');
      expect(verzamelMapnaam('Crooners & standards'), 'Crooners & standards');
      expect(verzamelMapnaam(' ... '), 'Verzameling');
    });
  });

  group('het id overleeft de verhuizing', () {
    test('DE KERN: hetzelfde bestand, hetzelfde id — in de bibliotheek of in een verzameling', () {
      const wortel = r'D:\Flac music 2024';
      final oud = trackIdFor(r'D:\Flac music 2024\DebridMusic Downloads\Singles\Billie Holiday\My Man.flac', wortel);
      final nieuw = trackIdFor(
          r'D:\Flac music 2024\DebridMusic Downloads\Verzamelingen\Vocal jazz\Singles\Billie Holiday\My Man.flac', wortel);
      expect(nieuw, oud, reason: 'anders raakten je favorieten, lijsten en wat je draaide los');
      final buiten = trackIdFor(r'D:\Flac music 2024\Ella\a.flac', wortel);
      expect(trackIdFor(r'D:\Flac music 2024\DebridMusic Downloads\Verzamelingen\Vocal jazz\_buiten\Ella\a.flac', wortel),
          buiten);
    });

    test('een album in een verzameling is een ander album; zonder verzameling blijft elk id wat het was', () {
      expect(albumIdFor('billie holiday', 'lady in satin', null), idOf('album', 'billie holiday|lady in satin|'));
      expect(albumIdFor('billie holiday', 'lady in satin', null, verzameling: 'Vocal jazz'),
          isNot(albumIdFor('billie holiday', 'lady in satin', null)));
      expect(albumIdFor('a', 't', null, verzameling: 'Vocal jazz'), albumIdFor('a', 't', null, verzameling: 'VOCAL JAZZ'),
          reason: 'hoofdletters tellen niet');
    });
  });

  group('vindbaar, niet gemengd', () {
    LibraryStore bibliotheek() => LibraryStore()
      ..tracks.addAll([
        _t(r'D:\m\DebridMusic Downloads\Singles\Billie Holiday\Gewoon.flac', titel: 'Gewoon'),
        _t(r'D:\m\DebridMusic Downloads\Verzamelingen\Vocal jazz\Singles\Billie Holiday\Apart.flac', titel: 'Apart'),
        _t(r'D:\m\Daft Punk\Discovery\One More Time.flac', artiest: 'Daft Punk', album: 'Discovery', titel: 'One More Time'),
      ])
      ..rebuildAlbums();

    test('DE KERN: de mix zonder de verzameling; alles blijft in tracks en albums (zoeken, afspelen)', () {
      final lib = bibliotheek();
      expect([for (final t in lib.mixTracks) t.title], ['Gewoon', 'One More Time']);
      expect(lib.tracks, hasLength(3));
      expect(lib.verzamelingNamen, ['Vocal jazz']);
      expect([for (final t in lib.tracksIn('vocal jazz')) t.title], ['Apart'], reason: 'hoofdletters tellen niet');
      expect(lib.albumsIn('Vocal jazz').single.verzameling, 'Vocal jazz');
      expect(lib.mixAlbums.every((a) => a.verzameling == null), isTrue);
      expect(lib.albums.where((a) => a.title == 'Lady in Satin'), hasLength(2),
          reason: 'hetzelfde album in de verzameling smelt niet samen met dat in je bibliotheek');
    });

    test('zonder verzamelingen precies dezelfde lijsten (wat op identiteit bewaart, blijft werken)', () {
      final lib = LibraryStore()
        ..tracks.add(_t(r'D:\m\a.flac'))
        ..rebuildAlbums();
      expect(identical(lib.mixTracks, lib.tracks), isTrue);
      expect(identical(lib.mixAlbums, lib.albums), isTrue);
    });

    test('een radio vult uit de mix, of uit zijn verzameling', () {
      final lib = bibliotheek();
      expect([for (final t in radioEigen(lib, null)) t.title], ['Gewoon', 'One More Time']);
      expect([for (final t in radioEigen(lib, 'Vocal jazz')) t.title], ['Apart']);
    });

    test('op een toestel komt de verzameling uit de catalogus', () {
      const dto = TrackDto(
          id: 't1',
          albumId: 'b1',
          artistId: 'a1',
          title: 'My Man',
          artistName: 'Billie Holiday',
          albumTitle: 'Lady Day',
          streamPath: '/stream/t1.flac',
          ext: 'flac',
          trackNo: 1,
          trackTotal: 0,
          discNo: 1,
          durationMs: 1000,
          verzameling: 'Vocal jazz');
      expect(dto.toJson()['verz'], 'Vocal jazz');
      expect(TrackDto.fromJson(dto.toJson()).verzameling, 'Vocal jazz');
      expect(TrackDto.fromJson({...dto.toJson()}..remove('verz')).verzameling, isNull);
      const zonder = TrackDto(
          id: 't2',
          albumId: 'b1',
          artistId: 'a1',
          title: 'x',
          artistName: 'y',
          albumTitle: 'z',
          streamPath: '/stream/t2.flac',
          ext: 'flac',
          trackNo: 1,
          trackTotal: 0,
          discNo: 1,
          durationMs: 1);
      expect(zonder.toJson().containsKey('verz'), isFalse, reason: 'een catalogus zonder verzamelingen blijft wat hij was');
      final apart = Track(path: 'http://pc.invalid/stream/t1.flac', title: 'My Man', artist: 'B', album: 'L', verzameling: 'Vocal jazz');
      expect(apart.verzameling, 'Vocal jazz');
    });
  });

  group('aangesloten (gelezen uit de bron)', () {
    test('de catalogus stuurt de verzameling mee, en neemt haar op in het album-id en de vingerafdruk', () {
      final c = _bron('lib/lan/catalog.dart');
      expect(c, contains('          verzameling: t.verzameling,\n'));
      expect(c, contains('      final albId = albumIdFor(aKey, normKey(album.title), album.edition, verzameling: album.verzameling);'));
      expect(c, contains("      if (t.verzameling != null) fingerprint.add('C\${t.verzameling}');"));
      expect(_bron('lib/library.dart'), contains('        verzameling: d.verzameling,\n'));
    });

    test('"Opruimen" laat een verzameling staan', () {
      expect(_bron('lib/organize.dart'), contains("        onder.contains('\$sep\$verzamelMap\$sep')) {"));
    });

    test('albums, artiesten, nummers, Start, Aanbevolen, Ontdek en nieuw op de gsm kijken naar de mix', () {
      final m = _bron('lib/main.dart');
      expect(m, contains('        final albums = (_q.isEmpty ? lib.mixAlbums : lib.albums).where((a) => a.tracks.any(_matches)).toList();'));
      expect(m, contains('  List<Album> get _source => widget.albums ?? widget.lib.mixAlbums;'));
      expect(m, contains('    final all = lijst ?? (query.isEmpty ? lib.mixTracks : lib.tracks);'));
      expect(m, contains('    final recent = [...lib.mixAlbums.where((a) => a.addedMs > 0)]'));
      expect(m, contains('    List<OntdekEigen> ontdekEigen() => [\n          for (final t in library.mixTracks)'));
      expect(m, contains('              bibliotheek: library.mixTracks,'));
      expect(m, contains('      alleNummers: () => library.mixTracks,'));
      expect(m, contains('List<Track> _reserveUit(LibraryStore lib, Set<String> artiesten, {String? verzameling, Verzamelingen? koppel}) => [\n'
          '      for (final t in radioEigen(lib, verzameling, koppel))'));
    });

    test('wat je al hebt, kijkt over alles: de radio-index en het bezit van Aanbevolen', () {
      final m = _bron('lib/main.dart');
      expect(m, contains('  for (final t in lib.tracks) {\n    if (nooitOpRadio(t.title)) continue;\n'
          '    (index[eigenSleutel(t.artist, t.title)] ??= []).add(t);'), reason: 'anders haalt een radio het opnieuw');
      expect(m, contains('      bezit: () => {for (final t in library.tracks) artistKey(hoofdartiest(t.artist))},'));
    });
  });
}
