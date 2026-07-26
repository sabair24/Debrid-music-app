// A sleeve traced to a pinned pressing has to survive closing the app.
//
// D'Eux, downloaded off Soulseek, carries "The Essential Céline Dion" as its embedded art — a rip of
// the compilation, tagged with the compilation's sleeve. The album page fetched the real one and
// handed it to the library, so the grid corrected itself the moment the record was opened; nothing
// was written down, so the next start showed the wrong sleeve again. Checking it always "worked",
// because checking it meant opening the album.
//
// The distinction these tests protect: a sleeve traced to a NAMED pressing is a fact and is kept;
// a by-name search result is a guess and must never be written down, or one bad guess outranks the
// files forever.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

/// Distinguishable, and over the 500-byte floor both writers insist on.
Uint8List bytesOf(int fill) => Uint8List.fromList(List.filled(2000, fill));

Album albumOf(String artist, String title, {Uint8List? embedded}) {
  final a = Album(title, artist, [
    Track(
      path: 'X:\\${artist}_$title\\01.flac',
      title: 'een',
      artist: artist,
      album: title,
      trackNo: 1,
    )
  ]);
  a.embeddedCover = embedded;
  return a;
}

void main() {
  late Directory scratch;
  late AppSettings settings;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_resolved_');
    setAppDirForTest(scratch.path);
    settings = AppSettings();
  });

  tearDown(() {
    // Windows keeps a handle open for a moment after a write; a failed cleanup must not fail a test.
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a traced sleeve comes back with its marker', () async {
    final album = albumOf('Céline Dion', "D'Eux");
    final art = bytesOf(7);
    await CoverEnricher(settings).saveResolvedCover(album, art, 'mb:0f5be2b5');

    final back = await CoverEnricher(settings).resolvedCover(albumOf('Céline Dion', "D'Eux"));
    expect(back, isNotNull);
    expect(back!.$1, art);
    expect(back.$2, 'mb:0f5be2b5');
  });

  test('bytes without a marker are not trusted', () async {
    final album = albumOf('Céline Dion', "D'Eux");
    await CoverEnricher(settings).saveResolvedCover(album, bytesOf(7), 'mb:x');
    // Lose the provenance and the image is indistinguishable from a by-name guess, which must not
    // outrank what the files carry.
    File('${CoverEnricher(settings).resolvedDir.path}${Platform.pathSeparator}'
            '${CoverEnricher(settings).keyFor(album)}.from')
        .deleteSync();
    expect(await CoverEnricher(settings).resolvedCover(album), isNull);
  });

  test('an empty marker is refused at the door', () async {
    final album = albumOf('Céline Dion', "D'Eux");
    await CoverEnricher(settings).saveResolvedCover(album, bytesOf(7), '   ');
    expect(await CoverEnricher(settings).resolvedCover(album), isNull);
  });

  test('adopting with a pressing writes it down', () async {
    final lib = LibraryStore();
    final album = albumOf('Céline Dion', "D'Eux", embedded: bytesOf(1));
    lib.albums = [album];

    lib.adoptAlbumCover('Céline Dion', "D'Eux", bytesOf(2),
        from: 'mb:0f5be2b5', settings: settings);
    // In memory straight away — this part already worked.
    expect(album.cover, bytesOf(2), reason: 'a traced sleeve outranks the embedded one');

    // And on disk, which is the part that did not. The write is fire-and-forget, so give it a turn.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final back = await CoverEnricher(settings).resolvedCover(album);
    expect(back, isNotNull, reason: 'closing the app would otherwise lose it');
    expect(back!.$1, bytesOf(2));
    expect(back.$2, 'mb:0f5be2b5');
  });

  test('a by-name guess is never written down', () async {
    final lib = LibraryStore();
    final album = albumOf('Céline Dion', "D'Eux", embedded: bytesOf(1));
    lib.albums = [album];

    // No `from`: this is "search the web for Céline Dion – D'Eux", which for a wrongly tagged rip
    // is as likely to be the compilation as the album.
    lib.adoptAlbumCover('Céline Dion', "D'Eux", bytesOf(3), settings: settings);
    expect(album.cover, bytesOf(1), reason: 'a guess stays below the embedded cover');

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await CoverEnricher(settings).resolvedCover(album), isNull);
  });

  test('a hand-picked cover still wins', () async {
    final lib = LibraryStore();
    final album = albumOf('Céline Dion', "D'Eux", embedded: bytesOf(1));
    album.correctedCover = bytesOf(9);
    lib.albums = [album];

    lib.adoptAlbumCover('Céline Dion', "D'Eux", bytesOf(2),
        from: 'mb:0f5be2b5', settings: settings);
    expect(album.cover, bytesOf(9));
    expect(album.resolvedCover, isNull, reason: 'the user had already answered this question');
  });

  test('without settings nothing is written — the old behaviour, on purpose', () async {
    final lib = LibraryStore();
    final album = albumOf('Céline Dion', "D'Eux", embedded: bytesOf(1));
    lib.albums = [album];

    lib.adoptAlbumCover('Céline Dion', "D'Eux", bytesOf(2), from: 'mb:0f5be2b5');
    expect(album.cover, bytesOf(2));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await CoverEnricher(settings).resolvedCover(album), isNull,
        reason: 'callers that cannot reach the settings still work, they just do not persist');
  });

  test('renaming the album carries the traced sleeve along', () async {
    final enricher = CoverEnricher(settings);
    final before = albumOf('Celine Dion', "D'eux");
    await enricher.saveResolvedCover(before, bytesOf(7), 'mb:0f5be2b5');

    await enricher.reKeyFixedCover('Celine Dion', "D'eux", 'Céline Dion', "D'Eux");

    expect(await enricher.resolvedCover(before), isNull, reason: 'the old key is gone');
    final after = await enricher.resolvedCover(albumOf('Céline Dion', "D'Eux"));
    expect(after, isNotNull, reason: 'a rename must not silently drop it, as it once did');
    expect(after!.$1, bytesOf(7));
    expect(after.$2, 'mb:0f5be2b5');
  });

  test('a tiny image is not a cover', () async {
    final album = albumOf('Céline Dion', "D'Eux");
    await CoverEnricher(settings).saveResolvedCover(album, Uint8List.fromList([1, 2, 3]), 'mb:x');
    expect(await CoverEnricher(settings).resolvedCover(album), isNull);
  });

  test('the next start restores it over the wrong embedded sleeve', () async {
    // The whole bug, end to end. A previous session traced the sleeve; this session is a cold start
    // with the same files, whose embedded art is the compilation's.
    await CoverEnricher(settings)
        .saveResolvedCover(albumOf('Céline Dion', "D'Eux"), bytesOf(2), 'mb:0f5be2b5');

    final lib = LibraryStore();
    final album = albumOf('Céline Dion', "D'Eux", embedded: bytesOf(1));
    lib.albums = [album];
    // Phase 2 fetches nothing: this album has a cover either way, which is exactly why the
    // restore has to happen BEFORE that check rather than as a fallback for a missing one.
    await lib.enrich(settings);

    expect(album.resolvedFrom, 'mb:0f5be2b5');
    expect(album.cover, bytesOf(2),
        reason: 'without the restore the grid shows the wrong sleeve until the album is opened');
  });

  test('a restore never overrules a cover picked by hand', () async {
    final enricher = CoverEnricher(settings);
    final album = albumOf('Céline Dion', "D'Eux", embedded: bytesOf(1));
    await enricher.saveResolvedCover(album, bytesOf(2), 'mb:0f5be2b5');
    await enricher.saveFixedCover(album, bytesOf(9));

    final lib = LibraryStore()..albums = [album];
    await lib.enrich(settings);
    expect(album.cover, bytesOf(9));
  });

  test('the key ignores case, so the same record is one entry', () async {
    final enricher = CoverEnricher(settings);
    await enricher.saveResolvedCover(albumOf('CÉLINE DION', "D'EUX"), bytesOf(7), 'mb:x');
    expect(await enricher.resolvedCover(albumOf('céline dion', "d'eux")), isNotNull);
  });
}
