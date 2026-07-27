// Een weggefilterde dubbele take bleef zichtbaar en werd onvindbaar.
//
// De pad-indexen werden uit `albums` gebouwd, en _dedupeTracks laat de tweede kopie van een take uit
// zijn album weg terwijl de platte trackslijst elk bestand houdt. Zo'n nummer stond dus wel in Tracks
// en was daar speelbaar, maar was onzichtbaar voor alle drie de opzoekingen: geen hoes, geen album op
// het speelscherm, en -- de vervelendste -- geen hervatten, want player.restore zoekt het laatst
// gespeelde pad op via trackByPath en kreeg null. Sluit de app op zo'n nummer en het kwam niet terug.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';

void main() {
  late Directory scratch;

  /// Echte bestanden, want de dedupe vergelijkt de bitrate en leest daarvoor de grootte van schijf.
  /// Met verzonnen paden faalt dat met PathNotFound voordat de test bij zijn punt is.
  String file(String name, {int bytes = 4000}) {
    final f = File('${scratch.path}${Platform.pathSeparator}$name');
    f.writeAsBytesSync(List.filled(bytes, 0));
    return f.path;
  }

  Track tr(String path, String title, {int no = 1, int secs = 200}) => Track(
        path: path,
        title: title,
        artist: 'Adele',
        album: '21',
        trackNo: no,
        duration: Duration(seconds: secs),
      );

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_dedupe_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('een gefolde dubbele take is nog steeds op te zoeken', () {
    final lib = LibraryStore();
    // Twee bestanden, dezelfde take: zelfde titel, zelfde lengte. De dedupe houdt er één in het album.
    final a = file('a1.flac', bytes: 5000);
    final b = file('b1.flac', bytes: 3000);
    lib.tracks.addAll([tr(a, 'Rolling in the Deep'), tr(b, 'Rolling in the Deep')]);
    lib.rebuildAlbums();

    final inAlbum = lib.albums.fold<int>(0, (n, x) => n + x.tracks.length);
    expect(inAlbum, 1, reason: 'de dedupe doet zijn werk nog: één take in het album');

    // Maar beide paden moeten vindbaar zijn.
    for (final p in [a, b]) {
      expect(lib.trackByPath(p), isNotNull, reason: 'hervatten hangt hieraan: $p');
      expect(lib.albumForPath(p), isNotNull, reason: 'het speelscherm hangt hieraan: $p');
    }
  });

  test('de gefolde kopie krijgt het album waar hij bij hoort', () {
    final lib = LibraryStore();
    final a = file('a2.flac', bytes: 5000);
    final b = file('b2.flac', bytes: 3000);
    lib.tracks.addAll([tr(a, 'Someone Like You', no: 2), tr(b, 'Someone Like You', no: 2)]);
    lib.rebuildAlbums();

    final al = lib.albumForPath(b);
    expect(al, isNotNull);
    expect(al!.title, '21', reason: 'niet een willekeurig album, maar dat van deze plaat');
    expect(al.artist, 'Adele');
  });

  test('en de hoes komt mee', () {
    final lib = LibraryStore();
    final a = file('a3.flac', bytes: 5000);
    final b = file('b3.flac', bytes: 3000);
    lib.tracks.addAll([tr(a, 'Set Fire to the Rain', no: 3), tr(b, 'Set Fire to the Rain', no: 3)]);
    lib.rebuildAlbums();
    lib.albums.first.enriched = Uint8List.fromList(List.filled(2000, 7));

    final folded = lib.tracks.firstWhere((x) => x.path == b);
    expect(lib.coverForTrack(folded), isNotNull,
        reason: 'in de platte Tracks-lijst hoorde hier een hoes te staan');
  });

  test('een gewoon nummer blijft gewoon vindbaar', () {
    final lib = LibraryStore();
    final a = file('a4.flac');
    lib.tracks.add(tr(a, 'Turning Tables', no: 4));
    lib.rebuildAlbums();
    expect(lib.trackByPath(a), isNotNull);
    expect(lib.albumForPath(a)?.title, '21');
  });

  test('een pad dat niet bestaat blijft null', () {
    final lib = LibraryStore();
    lib.tracks.add(tr(file('a5.flac'), 'Iets', no: 5));
    lib.rebuildAlbums();
    expect(lib.trackByPath(r'X:\weg\99.flac'), isNull);
    expect(lib.albumForPath(r'X:\weg\99.flac'), isNull);
  });
}
