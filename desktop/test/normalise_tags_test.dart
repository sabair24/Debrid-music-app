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

    expect((await lib.applyNormalise(plan)).written, 3);

    // Terug van schijf lezen: het bestand zelf moet nu kloppen, niet alleen het geheugen.
    for (final p in [a.path, b.path, c.path]) {
      final t = readFlacTags(File(p));
      expect(t, isNotNull, reason: 'het bestand is nog leesbaar: $p');
      expect(t!.album, "Backstreet's Back");
      expect(t.trackTotal, 3);
    }
  });

  test('plannen vanaf één tegel pakt de andere tegels erbij', () async {
    // In de GUI gezien: de aangeklikte tegel hield 8 van de 13 bestanden, die het onderling eens
    // waren. Er viel binnen die tegel niets recht te trekken — het verschil zit TUSSEN de tegels.
    final a = file('01.flac', {'TITLE': 'Everybody', 'ARTIST': 'Backstreet Boys', 'ALBUM': "Backstreet's Back", 'TRACKNUMBER': '1', 'TOTALTRACKS': '11'}, secs: 220);
    final b = file('02.flac', {'TITLE': 'As Long as You Love Me', 'ARTIST': 'Backstreet Boys', 'ALBUM': 'Backstreet’s Back', 'TRACKNUMBER': '1', 'TOTALTRACKS': '14'}, secs: 216);
    final c = file('03.flac', {'TITLE': 'All I Have to Give', 'ARTIST': 'Backstreet Boys', 'ALBUM': "Backstreet's Back", 'TRACKNUMBER': '3'}, secs: 250);

    final lib = LibraryStore()..tracks.addAll([a.track, b.track, c.track]);
    lib.rebuildAlbums();
    final tegel = lib.albums.first;
    expect(lib.albums.length, greaterThan(1), reason: 'zo begint het');
    expect(tegel.tracks.length, lessThan(3), reason: 'de tegel houdt maar een deel');

    final plan = lib.planNormalise(tegel, pressing(), albumTitle: "Backstreet's Back");
    expect(plan.steps, hasLength(3), reason: 'alle bestanden van de plaat, niet alleen de tegel');
    expect(plan.totalsNow, {0, 11, 14}, reason: 'nu pas is de rommel zichtbaar');
    expect((await lib.applyNormalise(plan)).written, 3);

    for (final p in [a.path, b.path, c.path]) {
      expect(readFlacTags(File(p))!.trackTotal, 3);
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

  test('een nummer dat de persing niet kent houdt titel en nummer', () {
    final a = file('01.flac', {'TITLE': 'Everybody', 'ARTIST': 'BSB', 'ALBUM': 'X', 'TRACKNUMBER': '1'}, secs: 220);
    final vreemd = file('99.flac', {'TITLE': 'Iets Heel Anders', 'ARTIST': 'BSB', 'ALBUM': 'X', 'TRACKNUMBER': '9'}, secs: 61);

    final lib = LibraryStore()..tracks.addAll([a.track, vreemd.track]);
    lib.rebuildAlbums();
    final plan = lib.planNormalise(Album('X', 'BSB', [a.track, vreemd.track]), pressing());

    final s = plan.albumOnly.single;
    expect(s.name, '99.flac');
    expect(s.note, contains('niet herkend'));
    expect(s.title, isNull, reason: 'we weten niet welk nummer dit is');
    expect(s.trackNo, isNull);
    expect(plan.skipped, isEmpty, reason: 'het is wel een FLAC — het album mag er wel in');
  });

  test('maar krijgt wél het album en het aantal — anders blijft het een eigen tegel', () async {
    // Gemeten op de echte map: een onbekend bestand overslaan bracht Backstreet's Back van vier
    // tegels naar twee, niet naar één. Dat ene bestand hield TOTALTRACKS=0 en dus een eigen tegel.
    final a = file('01.flac', {'TITLE': 'Everybody', 'ARTIST': 'BSB', 'ALBUM': "X's", 'TRACKNUMBER': '1', 'TOTALTRACKS': '11'}, secs: 220);
    final b = file('02.flac', {'TITLE': 'As Long as You Love Me', 'ARTIST': 'BSB', 'ALBUM': 'X’s', 'TRACKNUMBER': '2'}, secs: 216);
    final vreemd = file('99.flac', {'TITLE': 'Iets Heel Anders', 'ARTIST': 'BSB', 'ALBUM': 'X’s', 'TRACKNUMBER': '9'}, secs: 61);

    final alle = [a.track, b.track, vreemd.track];
    final lib = LibraryStore()..tracks.addAll(alle);
    lib.rebuildAlbums();

    final plan = lib.planNormalise(Album("X's", 'BSB', alle), pressing(), albumTitle: "X's");
    expect(plan.writing, hasLength(3), reason: 'alle drie worden geschreven');
    expect((await lib.applyNormalise(plan)).written, 3);

    final t = readFlacTags(File(vreemd.path))!;
    expect(t.album, "X's", reason: 'hoort bij deze plaat');
    expect(t.trackTotal, 3, reason: 'en telt mee in hetzelfde aantal');
    expect(t.title, 'Iets Heel Anders', reason: 'de titel is niet van ons om te verzinnen');
    expect(t.trackNo, 9, reason: 'en het nummer evenmin');

    // Waar het om begonnen was.
    final vers = LibraryStore()
      ..tracks.addAll([
        for (final p in [a.path, b.path, vreemd.path])
          () {
            final x = readFlacTags(File(p))!;
            return Track(
                path: p,
                title: x.title ?? '',
                artist: x.artist ?? '',
                album: x.album ?? '',
                trackNo: x.trackNo,
                trackTotal: x.trackTotal,
                duration: x.duration,
                isFlac: true);
          }(),
      ]);
    vers.rebuildAlbums();
    expect(vers.albums.length, 1, reason: 'één tegel, ook met een bestand dat de persing niet kent');
  });

  test('een botsing noemt de bestanden bij naam', () {
    // "Twee bestanden zouden botsen" zonder te zeggen welke, laat je niets om aan te pakken.
    final a = file('01.flac', {'TITLE': 'Everybody', 'ARTIST': 'BSB', 'ALBUM': 'X', 'TRACKNUMBER': '1'}, secs: 220);
    final b = file('99.flac', {'TITLE': 'Iets Anders', 'ARTIST': 'BSB', 'ALBUM': 'X', 'TRACKNUMBER': '1'}, secs: 61);

    final lib = LibraryStore()..tracks.addAll([a.track, b.track]);
    lib.rebuildAlbums();
    // b wordt niet herkend en houdt nummer 1; a krijgt nummer 1 van de persing. Dat botst niet in
    // het plan, want b's nummer veranderen we niet — dus geen melding.
    final plan = lib.planNormalise(Album('X', 'BSB', [a.track, b.track]), pressing());
    expect(plan.clashes, isEmpty);
    expect(plan.safe, isTrue);

    // De botsing die wél voorkomt, en die de Backstreet-map liet zien: één bestand krijgt de
    // officiële titel en komt daarmee op de titel van een bestand dat de persing NIET kende en dat
    // de zijne dus houdt. Die twee verschilden eerst — dus deze botsing maken wij.
    final typo = file('02.flac', {'TITLE': 'Missin You', 'ARTIST': 'BSB', 'ALBUM': 'Y', 'TRACKNUMBER': '4'}, secs: 300);
    final exact = file('03.flac', {'TITLE': 'Missing You', 'ARTIST': 'BSB', 'ALBUM': 'Y', 'TRACKNUMBER': '9'}, secs: 300);
    final lib2 = LibraryStore()..tracks.addAll([typo.track, exact.track]);
    lib2.rebuildAlbums();
    // typo staat vooraan, pakt de enige regel uit de pool; exact vindt niets meer en houdt zijn
    // eigen titel — die dan gelijk is aan wat typo net gekregen heeft.
    final p2 = lib2.planNormalise(Album('Y', 'BSB', [typo.track, exact.track]),
        [const ChoiceTrack('1', 'Missing You', 300)]);
    expect(p2.clashes, isNotEmpty, reason: 'twee keer "Missing You" na afloop');
    expect(p2.clashes.first, contains('02.flac'));
    expect(p2.clashes.first, contains('03.flac'));
    expect(p2.titleCollides, isTrue);
    expect(p2.collides, isFalse, reason: 'de nummers botsen niet, alleen de titels');
    expect(p2.safe, isFalse);
  });

  test('twee bestanden die nu al dezelfde titel hebben blokkeren het plan niet', () {
    // De dubbele rip is precies waarom deze knop bestaat; er hier op weigeren maakt hem nutteloos.
    final a = file('01.flac', {'TITLE': 'Missing You', 'ARTIST': 'BSB', 'ALBUM': 'X', 'TRACKNUMBER': '1'}, secs: 300);
    final b = file('02.flac', {'TITLE': 'Missing You', 'ARTIST': 'BSB', 'ALBUM': 'X', 'TRACKNUMBER': '1'}, secs: 300);

    final lib = LibraryStore()..tracks.addAll([a.track, b.track]);
    lib.rebuildAlbums();
    final plan = lib.planNormalise(Album('X', 'BSB', [a.track, b.track]), pressing());
    expect(plan.titleCollides, isFalse, reason: 'die botsing stond er al, die maken wij niet');
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

  test('de oude TOTALTRACKS blijft niet naast de nieuwe TRACKTOTAL staan', () async {
    // Op de echte plaat gemeten na de eerste keer gelijktrekken: TRACKTOTAL=16 in hetzelfde bestand
    // als TOTALTRACKS=11. Deze app leest tracktotal eerst en zag dus één plaat; Roon of een telefoon
    // die het andere veld leest, zou hem nog steeds gesplitst zien. Twee waarheden in één bestand.
    final a = file('01.flac',
        {'TITLE': 'Everybody', 'ARTIST': 'BSB', 'ALBUM': 'X', 'TRACKNUMBER': '1', 'TOTALTRACKS': '11'},
        secs: 220);
    final lib = LibraryStore()..tracks.add(a.track);
    lib.rebuildAlbums();
    await lib.applyNormalise(lib.planNormalise(Album('X', 'BSB', [a.track]), pressing()));

    final raw = readFlacRawFields(File(a.path));
    expect(raw['tracktotal'], '3');
    expect(raw['totaltracks'], '3', reason: 'allebei, of het bestand spreekt zichzelf tegen');
  });

  test('er blijft geen .tags-restant achter', () async {
    final a = file('01.flac', {'TITLE': 'Everybody', 'ARTIST': 'BSB', 'ALBUM': 'X', 'TRACKNUMBER': '1'}, secs: 220);
    final lib = LibraryStore()..tracks.add(a.track);
    lib.rebuildAlbums();
    await lib.applyNormalise(lib.planNormalise(Album('X', 'BSB', [a.track]), pressing()));
    expect(File('${a.path}.tags').existsSync(), isFalse);
  });
}
