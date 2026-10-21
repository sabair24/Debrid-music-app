/// De hoesregel van Saber, 21-10-2026.
///
/// Voorkant: Deezer 1200 (als artiest én titel kloppen), anders TheAudioDB, anders de scherpste scan, en pas
/// dan de hoes in het bestand — "digitaal wint altijd". Cd en achterkant: TheAudioDB eerst, anders de
/// scherpste van MusicBrainz en Discogs. Aanleiding: op de gsm werd de digitale hoes van KATSEYE —
/// BEAUTIFUL CHAOS na 27 s een scheve Discogs-foto van de fysieke hoes.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/cachesleutel.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> dz(int id, String artiest, String titel) => {
      'id': id,
      'title': titel,
      'artist': {'name': artiest},
      'cover_xl': 'https://cdn-images.dzcdn.net/images/cover/$id/1000x1000-000000-80-0-0.jpg',
    };

Uint8List bytesVan(int vulling) => Uint8List.fromList(List.filled(2000, vulling));

void main() {
  group('het juiste Deezer-album, nooit blind het eerste', () {
    test('Roya — Turn Me On: Deezer geeft "Rojas On The Beat — On Me" als eerste, en dat is het niet', () {
      expect(kiesDigitaalAlbum([dz(1, 'Rojas On The Beat', 'On Me')], 'Roya', 'Turn Me On'), isNull);
    });

    test('een naamgenoot met dezelfde titel is een ander album', () {
      expect(kiesDigitaalAlbum([dz(1, 'Oasis Trance', 'Definitely Maybe')], 'Oasis', 'Definitely Maybe'), isNull);
    });

    test('de precieze titel gaat voor de deluxe, de deluxe is de terugval', () {
      final data = [dz(1, 'Sabrina Carpenter', "Short n' Sweet (Deluxe)"), dz(2, 'Sabrina Carpenter', "Short n' Sweet")];
      expect(kiesDigitaalAlbum(data, 'Sabrina Carpenter', "Short n' Sweet")?['id'], 2);
      expect(kiesDigitaalAlbum([data.first], 'Sabrina Carpenter', "Short n' Sweet")?['id'], 1);
    });

    test('hoofdletters tellen niet; een samenwerking begint met de artiest van Deezer', () {
      expect(kiesDigitaalAlbum([dz(5, 'KATSEYE', 'BEAUTIFUL CHAOS')], 'Katseye', 'Beautiful Chaos')?['id'], 5);
      expect(kiesDigitaalAlbum([dz(6, 'Lady Gaga', 'Die With A Smile')], 'Lady Gaga & Bruno Mars', 'Die With A Smile')?['id'],
          6);
    });

    test('bij een verzamelaar telt alleen de precieze titel', () {
      final data = [dz(7, 'Various Artists', 'Serious Beats 48 (Deluxe)'), dz(8, 'Various Artists', 'Serious Beats 48')];
      expect(kiesDigitaalAlbum(data, 'Various Artists', 'Serious Beats 48', generiek: true)?['id'], 8);
      expect(kiesDigitaalAlbum([data.first], 'Various Artists', 'Serious Beats 48', generiek: true), isNull);
    });
  });

  test('wat digitaal is: Deezer en TheAudioDB, geen scan van een persing', () {
    for (final h in ['dz:123', 'tadb', 'tadb:abc']) {
      expect(isDigitaleHerkomst(h), isTrue, reason: h);
    }
    for (final h in ['rel:9902241', 'mb:0f5be2b5', 'dg:777', '', null]) {
      expect(isDigitaleHerkomst(h), isFalse, reason: '$h');
    }
  });

  group('de bibliotheek', () {
    late Directory krab;
    late LibraryStore library;
    final uitDeBestanden = bytesVan(11), scan = bytesVan(22), digitaal = bytesVan(33);

    setUp(() {
      krab = Directory.systemTemp.createTempSync('dm_hoesregel_');
      setAppDirForTest(krab.path);
      library = LibraryStore()
        ..configDirOverride = krab.path
        ..rootPath = krab.path;
      library.tracks.add(Track(
        path: '${krab.path}${Platform.pathSeparator}1.flac',
        title: 'Gabriela',
        artist: 'KATSEYE',
        album: 'BEAUTIFUL CHAOS',
        trackNo: 2,
      ));
      library.rebuildAlbums();
      library.albums.single.embeddedCover = uitDeBestanden;
    });

    tearDown(() {
      try {
        krab.deleteSync(recursive: true);
      } catch (_) {}
    });

    Album plaat() => library.albums.single;

    test('een digitale voorkant gaat vóór de bestanden', () {
      expect(library.adoptAlbumCover('KATSEYE', 'BEAUTIFUL CHAOS', digitaal, from: 'dz:769623101'), isTrue);
      expect(plaat().cover, same(digitaal));
    });

    test('een digitale voorkant verdringt een scan', () {
      library.adoptAlbumCover('KATSEYE', 'BEAUTIFUL CHAOS', scan, from: 'rel:34398727');
      expect(plaat().cover, same(scan), reason: 'een scan gaat nog altijd vóór de bestanden (Roya: alleen op Discogs)');
      library.adoptAlbumCover('KATSEYE', 'BEAUTIFUL CHAOS', digitaal, from: 'dz:769623101');
      expect(plaat().cover, same(digitaal));
      expect(plaat().resolvedFrom, 'dz:769623101');
    });

    test('DE KERN: een scan neemt nooit de plaats van een digitale voorkant in', () {
      library.adoptAlbumCover('KATSEYE', 'BEAUTIFUL CHAOS', digitaal, from: 'dz:769623101');
      expect(library.adoptAlbumCover('KATSEYE', 'BEAUTIFUL CHAOS', scan, from: 'rel:34398727'), isFalse);
      expect(plaat().cover, same(digitaal));
      expect(plaat().resolvedFrom, 'dz:769623101');
    });

    test('een hoes die je zelf koos blijft staan, ook boven digitaal', () {
      plaat().correctedCover = bytesVan(44);
      library.adoptAlbumCover('KATSEYE', 'BEAUTIFUL CHAOS', digitaal, from: 'dz:769623101');
      expect(plaat().cover, same(plaat().correctedCover));
    });
  });

  test('wat er al op schijf ligt: de digitale voorkant, en elke keer hetzelfde object (geen flits)', () async {
    final krab = Directory.systemTemp.createTempSync('dm_hoesregel_schijf_');
    addTearDown(() {
      try {
        krab.deleteSync(recursive: true);
      } catch (_) {}
    });
    setAppDirForTest(krab.path);
    final enricher = CoverEnricher(AppSettings());
    final sleutel = fnv1a('katseye|beautiful chaos');
    await enricher.digitaalDir.create(recursive: true);
    final beeld = Uint8List.fromList([0xFF, 0xD8, ...List.filled(3000, 7)]);
    await File('${enricher.digitaalDir.path}${Platform.pathSeparator}$sleutel.jpg').writeAsBytes(beeld);
    await File('${enricher.digitaalDir.path}${Platform.pathSeparator}$sleutel.from').writeAsString('dz:769623101');

    final a = await enricher.digitaleVoorkant('KATSEYE', 'BEAUTIFUL CHAOS', netwerk: false);
    final b = await enricher.digitaleVoorkant('KATSEYE', 'BEAUTIFUL CHAOS', netwerk: false);
    expect(a?.bron, 'dz:769623101');
    expect(identical(a?.bytes, b?.bytes), isTrue);

    final dienst = DiscogsService(AppSettings());
    final x = await dienst.cachedReleaseArt('KATSEYE', 'BEAUTIFUL CHAOS');
    final y = await dienst.cachedReleaseArt('KATSEYE', 'BEAUTIFUL CHAOS');
    expect(x?.front, same(a!.bytes));
    expect(x?.bron, 'dz:769623101');
    expect(identical(x, y), isTrue, reason: 'Image.memory herkent een beeld aan zijn object');
  });

  test('aangesloten: de voorkant ligt over elk antwoord heen, en komt meteen als tussenstand', () {
    final d = File('lib/discogs.dart').readAsStringSync();
    expect(d, contains('return _metDigitaal(cached, await digitaalF);'), reason: 'ook een afgerond antwoord uit de cache');
    expect(d, contains('.then((a) async => _metDigitaal(a, await digitaalF))'));
    expect(d, contains('meld(ReleaseArt(front: d.bytes, bron: d.bron));'));
    final m = File('lib/main.dart').readAsStringSync();
    expect(m, contains('final digitaal = t.front != null && isDigitaleHerkomst(t.bron) && !isDigitaleHerkomst(nu?.bron);'));
    final l = File('lib/library.dart').readAsStringSync();
    expect(l, contains('if (!digitaal && isDigitaleHerkomst(a.resolvedFrom)) continue;'));
    expect(l, contains('(isDigitaleHerkomst(traced.\$2) || _pinPastBij(album, traced.\$2))'),
        reason: 'ook bij het teruglezen na een herstart');
    final w = File('lib/facts_warmer.dart').readAsStringSync();
    final al = w.substring(w.indexOf('if (await DiscogsService(settings).hasReleaseArt('));
    expect(al.indexOf('digitaleVoorkant(album.artist, album.title)'), lessThan(al.indexOf('_neemHoesOver(')),
        reason: 'de opwarmer haalt de digitale voorkant ook voor platen waarvan de scans er al staan');
  });
}
