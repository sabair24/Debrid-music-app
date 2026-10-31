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

  // Saber, 21-10-2026, over Jordy — Dur Dur D'être Bébé uit "Foute Cd 11 Cd2": "het moet echt de originele
  // hoes zijn". Zo antwoordde Deezer die dag op "Jordy Dur Dur D'etre Bebe".
  group('een verzamelrip krijgt de hoes van de originele uitgave van het nummer', () {
    Map<String, dynamic> nr(String artiest, String titel, int album) =>
        {'title': titel, 'artist': {'name': artiest}, 'album': {'id': album}};
    final uitslag = [
      nr('Jordy', "Dur Dur d'être bébé !", 664022531),
      nr('Jordy', "Dur Dur d'être bébé ! (remix)", 664022531),
      nr('The Karaoke Channel', "Dur Dur D'être Bébé (Originally Performed by Jordy) [Karaoke Version]", 13619495),
      nr('Starlite Karaoke', "Dur Dur D'Être Bébé! (In the Style of Jordy) (Instrumental Version)", 372427417),
    ];

    test('DE KERN: het nummer zelf, geen remix of karaokeversie', () {
      expect(albumsVanNummer(uitslag, 'Jordy', "Dur Dur D'être Bébé"), [664022531]);
    });

    test('de originele uitgave: van de artiest zelf, geen verzamelaar, de vroegste', () {
      Map<String, dynamic> alb(int id, String artiest, String soort, String datum) =>
          {'id': id, 'artist': {'name': artiest}, 'record_type': soort, 'release_date': datum};
      final o = kiesOrigineleUitgave([
        alb(1, 'Various Artists', 'compile', '1990-01-01'),
        alb(2, 'Jordy', 'compile', '1991-01-01'),
        alb(3, 'Jordy', 'album', '1993-03-01'),
        alb(4, 'Jordy', 'single', '1992-06-01'),
      ], 'Jordy');
      expect(o?['id'], 4);
    });

    test('wat er als verzamelaar uitziet', () {
      for (final t in ['Foute Cd 11 Cd2', 'NOW 121', "Bravo Hits 00's", 'Sublime Top 1000', 'Q-music Vol. 11', 'The Best Of 2024']) {
        expect(lijktVerzamelaar(t), isTrue, reason: t);
      }
      for (final t in ['Pochette Surprise', 'BEAUTIFUL CHAOS', 'Play', "Short n' Sweet"]) {
        expect(lijktVerzamelaar(t), isFalse, reason: t);
      }
    });

    test('aangesloten: Nu speelt, de albumpagina en de opwarmer geven de titels mee', () {
      final e = File('lib/enrichment.dart').readAsStringSync();
      expect(e, contains('if (gevonden == null && perNummer.isNotEmpty) gevonden = await _origineleVoorkant(artist, perNummer);'));
      expect(e, contains('(titels.length <= 2 || lijktVerzamelaar(album))'));
      expect(File('lib/discogs.dart').readAsStringSync(), contains('.digitaleVoorkant(artist, album, voorrang: !freeOnly, titels: titels)'));
      final m = File('lib/main.dart').readAsStringSync();
      expect(m, contains('titels: widget.titels,'));
      expect(m, contains('titels: [t.title, if (al != null) for (final x in al.tracks) if (x.title != t.title) x.title],'),
          reason: 'Nu speelt: het spelende nummer eerst');
      final fw = File('lib/facts_warmer.dart').readAsStringSync();
      expect(fw, contains('CoverEnricher(settings).digitaleVoorkant(a, b, titels: t)'));
      expect(fw, contains('album.artist, album.title, [for (final t in album.tracks) t.title]'));
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
    expect(d, contains('            .then((a) async {\n      unawaited(gezienMerk(dir, artist, album));\n      return _metDigitaal(a, await digitaalF);\n'));
    expect(d, contains('meld(ReleaseArt(front: d.bytes, bron: d.bron));'));
    final m = File('lib/main.dart').readAsStringSync();
    expect(m, contains('final digitaal = t.front != null && isDigitaleHerkomst(t.bron) && !isDigitaleHerkomst(nu?.bron);'));
    final l = File('lib/library.dart').readAsStringSync();
    expect(l, contains('if (!digitaal && isDigitaleHerkomst(a.resolvedFrom)) continue;'));
    expect(l, contains('(isDigitaleHerkomst(traced.\$2) || _pinPastBij(album, traced.\$2))'),
        reason: 'ook bij het teruglezen na een herstart');
    final w = File('lib/facts_warmer.dart').readAsStringSync();
    final al = w.substring(w.indexOf('Future<_Art> _warmArtFor('));
    expect(al.indexOf('await _voorkant(album);'), allOf(greaterThanOrEqualTo(0), lessThan(al.indexOf('_neemHoesOver('))),
        reason: 'de opwarmer haalt de digitale voorkant ook voor platen waarvan de scans er al staan');
  });
}
