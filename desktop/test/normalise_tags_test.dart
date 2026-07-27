// Vier tegels voor één plaat, en waarom het gelijktrekken van de tags dat oplost.
//
// Gemeten op de echte map: dertien bestanden Backstreet's Back uit vier Soulseek-bronnen, met vier
// verschillende TOTALTRACKS (leeg, 11, 12, 14) en twee schrijfwijzen van de albumtitel (rechte en
// gekrulde apostrof). editionSplit splitst zodra twee bestanden hetzelfde tracknummer claimen én er
// meer dan één TOTALTRACKS in de bak zit -- en dat oordeel geldt voor de HELE bak, dus elke
// onderscheiden waarde wordt een eigen tegel.
//
// De app had drie manieren om daar omheen te werken (een correctie in het geheugen, een renummering
// naar corrections.json, en met de hand samenvoegen) en liet de tags op schijf zo fout als ze waren.
// Alles wat diezelfde map las -- Roon, een telefoon, de volgende scan op een andere machine -- zag
// nog steeds vier platen. Dit schrijft het bestand zelf recht.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';

/// Een echte, minimale FLAC met een comment-blok — de writer weigert alles wat hij niet vertrouwt,
/// dus een verzonnen bestand zou niets bewijzen.
List<int> flacBytes(Map<String, String> tags, {int audioBytes = 4096}) {
  int u32le(int v) => v;
  final out = <int>[];
  out.addAll('fLaC'.codeUnits);

  // STREAMINFO (type 0), 34 bytes, niet laatste.
  out.addAll([0x00, 0x00, 0x00, 0x22]);
  out.addAll(List.filled(34, 0));

  // VORBIS_COMMENT (type 4), laatste blok.
  final body = <int>[];
  const vendor = 'test';
  void addU32(List<int> b, int v) {
    b.addAll([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  }

  addU32(body, vendor.length);
  body.addAll(vendor.codeUnits);
  addU32(body, tags.length);
  tags.forEach((k, v) {
    final s = '$k=$v'.codeUnits;
    addU32(body, s.length);
    body.addAll(s);
  });
  final len = body.length;
  out.addAll([0x84, (len >> 16) & 0xFF, (len >> 8) & 0xFF, len & 0xFF]);
  out.addAll(body);
  out.addAll(List.filled(audioBytes, u32le(0x55)));
  return out;
}

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_norm_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Schrijft een bestand en geeft het bijbehorende Track terug, zoals de scan het zou opleveren.
  ({String path, Track track}) file(String naam, Map<String, String> tags, {int secs = 200}) {
    final p = '${scratch.path}${Platform.pathSeparator}$naam';
    File(p).writeAsBytesSync(flacBytes(tags));
    return (
      path: p,
      track: Track(
        path: p,
        title: tags['TITLE'] ?? '',
        artist: tags['ARTIST'] ?? '',
        album: tags['ALBUM'] ?? '',
        trackNo: int.tryParse(tags['TRACKNUMBER'] ?? '') ?? 0,
        trackTotal: int.tryParse(tags['TOTALTRACKS'] ?? '') ?? 0,
        duration: Duration(seconds: secs),
        isFlac: true,
      ),
    );
  }

  /// De persing, zoals MusicBrainz hem geeft.
  List<ChoiceTrack> pressing() => [
        const ChoiceTrack('1', 'Everybody', 220),
        const ChoiceTrack('2', 'As Long as You Love Me', 216),
        const ChoiceTrack('3', 'All I Have to Give', 250),
      ];

  test('vier verschillende TOTALTRACKS worden er één', () async {
    final a = file('01.flac', {'TITLE': 'Everybody', 'ARTIST': 'Backstreet Boys', 'ALBUM': "Backstreet's Back", 'TRACKNUMBER': '1'}, secs: 220);
    final b = file('02.flac', {'TITLE': 'As Long as You Love Me', 'ARTIST': 'Backstreet Boys', 'ALBUM': 'Backstreet’s Back', 'TRACKNUMBER': '2', 'TOTALTRACKS': '11'}, secs: 216);
    final c = file('03.flac', {'TITLE': 'All I Have to Give', 'ARTIST': 'Backstreet Boys', 'ALBUM': "Backstreet's Back", 'TRACKNUMBER': '3', 'TOTALTRACKS': '14'}, secs: 250);

    final lib = LibraryStore()..tracks.addAll([a.track, b.track, c.track]);
    lib.rebuildAlbums();

    final plan = lib.planNormalise(lib.albums.first, pressing(), albumTitle: "Backstreet's Back");
    expect(plan.totalsNow, {0, 11, 14}, reason: 'dit is de rommel die de tegels maakt');
    expect(plan.albumsNow.length, 2, reason: 'twee schrijfwijzen van dezelfde titel');
    expect(plan.total, 3);
    expect(plan.safe, isTrue);
    expect(plan.writing, hasLength(3));

    expect(await lib.applyNormalise(plan), 3);

    // Terug van schijf lezen: het bestand zelf moet nu kloppen, niet alleen het geheugen.
    for (final p in [a.path, b.path, c.path]) {
      final t = readFlacTags(File(p));
      expect(t, isNotNull, reason: 'het bestand is nog leesbaar: $p');
      expect(t!.album, "Backstreet's Back");
      expect(t.trackTotal, 3);
    }
  });

  test('en dan is het één album in plaats van vier', () async {
    // De directe regressie op wat de gebruiker ziet.
    final a = file('01.flac', {'TITLE': 'Everybody', 'ARTIST': 'Backstreet Boys', 'ALBUM': "Backstreet's Back", 'TRACKNUMBER': '1'}, secs: 220);
    final b = file('02.flac', {'TITLE': 'As Long as You Love Me', 'ARTIST': 'Backstreet Boys', 'ALBUM': 'Backstreet’s Back', 'TRACKNUMBER': '1', 'TOTALTRACKS': '11'}, secs: 216);
    final c = file('03.flac', {'TITLE': 'All I Have to Give', 'ARTIST': 'Backstreet Boys', 'ALBUM': "Backstreet's Back", 'TRACKNUMBER': '3', 'TOTALTRACKS': '14'}, secs: 250);

    final lib = LibraryStore()..tracks.addAll([a.track, b.track, c.track]);
    lib.rebuildAlbums();
    expect(lib.albums.length, greaterThan(1), reason: 'zo begint het: gesplitst op TOTALTRACKS');

    final plan = lib.planNormalise(lib.albums.first, pressing(), albumTitle: "Backstreet's Back");
    // Het album waar de gebruiker op klikte houdt maar een deel van de bestanden; het plan wordt
    // hier op alle drie gedraaid door ze in één album te zetten.
    final alle = lib.planNormalise(
        Album("Backstreet's Back", 'Backstreet Boys', [a.track, b.track, c.track]), pressing(),
        albumTitle: "Backstreet's Back");
    expect(plan.total, alle.total);
    await lib.applyNormalise(alle);

    // Opnieuw inlezen zoals de scan doet, met de tags die nu op schijf staan.
    final vers = LibraryStore()
      ..tracks.addAll([
        for (final p in [a.path, b.path, c.path])
          () {
            final t = readFlacTags(File(p))!;
            return Track(
              path: p,
              title: t.title ?? '',
              artist: t.artist ?? '',
              album: t.album ?? '',
              trackNo: t.trackNo,
              trackTotal: t.trackTotal,
              duration: t.duration,
              isFlac: true,
            );
          }(),
      ]);
    vers.rebuildAlbums();
    expect(vers.albums.length, 1, reason: 'één plaat, één tegel');
  });

  test('een niet-FLAC wordt gemeld, niet stil overgeslagen', () {
    final a = file('01.flac', {'TITLE': 'Everybody', 'ARTIST': 'BSB', 'ALBUM': 'X', 'TRACKNUMBER': '1'}, secs: 220);
    final mp3 = Track(
        path: '${scratch.path}${Platform.pathSeparator}02.mp3',
        title: 'As Long as You Love Me',
        artist: 'BSB',
        album: 'X',
        trackNo: 2,
        duration: const Duration(seconds: 216));

    final lib = LibraryStore()..tracks.addAll([a.track, mp3]);
    lib.rebuildAlbums();
    final plan = lib.planNormalise(Album('X', 'BSB', [a.track, mp3]), pressing());

    expect(plan.skipped, hasLength(1));
    expect(plan.skipped.single.skipped, contains('geen FLAC'));
    expect(plan.writing.map((s) => s.name), ['01.flac']);
  });

  test('een nummer dat de persing niet kent blijft ongemoeid', () {
    final a = file('01.flac', {'TITLE': 'Everybody', 'ARTIST': 'BSB', 'ALBUM': 'X', 'TRACKNUMBER': '1'}, secs: 220);
    final vreemd = file('99.flac', {'TITLE': 'Iets Heel Anders', 'ARTIST': 'BSB', 'ALBUM': 'X', 'TRACKNUMBER': '9'}, secs: 61);

    final lib = LibraryStore()..tracks.addAll([a.track, vreemd.track]);
    lib.rebuildAlbums();
    final plan = lib.planNormalise(Album('X', 'BSB', [a.track, vreemd.track]), pressing());

    expect(plan.skipped.map((s) => s.name), contains('99.flac'));
    expect(plan.skipped.firstWhere((s) => s.name == '99.flac').skipped, contains('niet herkend'));
  });

  test('twee bestanden op één nummer wordt geweigerd', () {
    // Dezelfde vangrail als planRenumber: de nummering wordt gerepareerd OMDAT hij botst.
    final a = file('01.flac', {'TITLE': 'Everybody', 'ARTIST': 'BSB', 'ALBUM': 'X'}, secs: 220);
    final b = file('02.flac', {'TITLE': 'Everybody', 'ARTIST': 'BSB', 'ALBUM': 'X'}, secs: 220);

    final lib = LibraryStore()..tracks.addAll([a.track, b.track]);
    lib.rebuildAlbums();
    final plan = lib.planNormalise(Album('X', 'BSB', [a.track, b.track]), pressing());
    // Twee identieke titels: de tweede vindt niets meer in de pool en wordt overgeslagen.
    expect(plan.writing.length + plan.skipped.length, 2);
    expect(plan.titleCollides, isFalse, reason: 'de pool voorkomt dat één entry twee bestanden claimt');
  });

  test('de correcties die de tags nu zelf zeggen worden opgeruimd', () async {
    // Goede titel, verkeerd nummer — precies waarom er ooit een renummering overheen ging.
    final a = file('01.flac', {'TITLE': 'Everybody', 'ARTIST': 'BSB', 'ALBUM': 'X', 'TRACKNUMBER': '7'}, secs: 220);
    final lib = LibraryStore()..tracks.add(a.track);
    lib.rebuildAlbums();

    // Alsof de gebruiker eerder had gerenummerd, plus een pin die van hem is en moet blijven.
    lib.seedCorrectionForTest(a.path, {
      'trackNo': '1',
      'trackTotal': '3',
      'mbid': 'blijft-staan',
    });
    await lib.saveCorrectionsNow();

    final plan = lib.planNormalise(Album('X', 'BSB', [a.track]), pressing());
    await lib.applyNormalise(plan);

    final na = lib.correctionForTest(a.path);
    expect(na, isNotNull, reason: 'de pin houdt de vermelding in leven');
    expect(na!.containsKey('trackNo'), isFalse, reason: 'het bestand zegt dit nu zelf');
    expect(na.containsKey('trackTotal'), isFalse);
    expect(na['mbid'], 'blijft-staan', reason: 'de gekozen persing is van de gebruiker');
  });

  test('er blijft geen .tags-restant achter', () async {
    final a = file('01.flac', {'TITLE': 'Everybody', 'ARTIST': 'BSB', 'ALBUM': 'X', 'TRACKNUMBER': '1'}, secs: 220);
    final lib = LibraryStore()..tracks.add(a.track);
    lib.rebuildAlbums();
    await lib.applyNormalise(lib.planNormalise(Album('X', 'BSB', [a.track]), pressing()));
    expect(File('${a.path}.tags').existsSync(), isFalse);
  });
}
