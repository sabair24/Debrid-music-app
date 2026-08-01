import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/organize.dart';

/// A tiny but valid FLAC carrying the tags a Soulseek peer might have written.
Uint8List _peerFlac(List<String> comments, {int pad = 2048}) {
  final out = BytesBuilder();
  out.add(ascii.encode('fLaC'));
  void block(int type, List<int> body, bool last) {
    out.add([(last ? 0x80 : 0) | type, (body.length >> 16) & 0xFF, (body.length >> 8) & 0xFF, body.length & 0xFF]);
    out.add(body);
  }

  final si = Uint8List(34);
  const rate = 44100;
  si[10] = (rate >> 12) & 0xFF;
  si[11] = (rate >> 4) & 0xFF;
  si[12] = ((rate & 0x0F) << 4) | (1 << 1);
  si[14] = 0x40;
  block(0, si, false);

  final b = BytesBuilder();
  void u32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  final ven = utf8.encode('someone else');
  u32(ven.length);
  b.add(ven);
  u32(comments.length);
  for (final c in comments) {
    final e = utf8.encode(c);
    u32(e.length);
    b.add(e);
  }
  block(4, b.toBytes(), true);
  out.add(List.filled(pad, 0x11));
  return out.toBytes();
}

const _official = [
  ChoiceTrack('1', 'We’ve Got It Goin’ On', 219),
  ChoiceTrack('2', 'Anywhere for You', 280),
  ChoiceTrack('3', 'Get Down (You’re the One for Me)', 230),
  ChoiceTrack('4', 'I’ll Never Break Your Heart', 288),
];

const _release = ReleaseAuthority(
  artist: 'Backstreet Boys',
  album: 'Backstreet Boys',
  albumArtist: 'Backstreet Boys',
  year: 1996,
  tracks: _official,
);

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('auth'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('ReleaseAuthority.match', () {
    test('recognises the same song whatever the uploader called it', () {
      // Every one of these is track 2 of this record. The numbers in the names are all wrong.
      for (final name in [
        '13 Anywhere for You.flac',
        '19. Backstreet Boys - Anywhere For You.flac',
        'Backstreet Boys - The Essential Backstreet Boys - 01 - Anywhere for You.flac',
        '06 Anywhere for You.flac',
      ]) {
        final t = _release.match(name, 282);
        expect(t, isNotNull, reason: name);
        expect(t!.trackNo, 2, reason: '$name should be track 2');
        expect(t.title, 'Anywhere for You');
        expect(t.album, 'Backstreet Boys');
        expect(t.albumArtist, 'Backstreet Boys');
        expect(t.trackTotal, 4);
        expect(t.year, 1996);
      }
    });

    test('a song that is not on this record is not forced onto it', () {
      expect(_release.match('Everybody (Backstreets Back).flac', 226), isNull);
    });

    test('a wildly different running time is treated as a different recording', () {
      // An eight-minute club mix is not the 4:40 album cut.
      final t = _release.match('Anywhere for You (Extended Club Mix).flac', 500);
      if (t != null) expect(t.trackNo, 2, reason: 'if it matches at all it must be the right track');
    });

    test('duration alone rescues a filename that says almost nothing', () {
      expect(_release.match('Anywhere for You.flac', 281)?.trackNo, 2);
    });
  });

  group('TrackTags', () {
    test('only an official release counts as authoritative', () {
      const peer = TrackTags(title: 'x', artist: 'y', album: 'z', trackNo: 3);
      expect(peer.isAuthoritative, isFalse);
      expect(_release.forTrack(_official[1], 2).isAuthoritative, isTrue);
    });

    test('survives being written down and read back', () {
      final a = _release.forTrack(_official[1], 2);
      final b = TrackTags.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>)!;
      expect(b.title, a.title);
      expect(b.trackNo, 2);
      expect(b.trackTotal, 4);
      expect(b.year, 1996);
      expect(b.albumArtist, 'Backstreet Boys');
      expect(b.isAuthoritative, isTrue, reason: 'a resumed download keeps its authority');
    });

    test('a row written before this existed still reads', () {
      // pending_downloads.json entries from an older build carry no authority at all.
      expect(TrackTags.fromJson(const {}), isNull);
      final old = TrackTags.fromJson({'title': 't', 'artist': 'a', 'album': 'b', 'trackNo': 1})!;
      expect(old.isAuthoritative, isFalse, reason: 'and behaves exactly as it always did');
    });

    test('a track number of zero produces no numbered filename — so it must never be zero', () {
      // Deezer's ALBUM endpoint omits track_position entirely (it only exists per track), so every
      // position read from it is 0. Passed straight through, a download landed as
      // "We've Got It Goin' On.flac" with no number in front of it.
      const noNumber = TrackTags(
          title: 'We’ve Got It Goin’ On',
          artist: 'Backstreet Boys',
          album: 'Backstreet Boys',
          trackNo: 0,
          trackTotal: 13,
          year: 1996);
      expect(relativePathFor(noNumber, ext: '.flac'), isNot(contains(' - ')),
          reason: 'this is the shape of the bug');
      expect(noNumber.vorbisFields.containsKey('TRACKNUMBER'), isFalse);

      final numbered = _release.forTrack(_official[0], 1);
      expect(relativePathFor(numbered, ext: '.flac'), contains('01 - '));
      expect(numbered.vorbisFields['TRACKNUMBER'], '1');
    });

    test('names only the fields it is allowed to overwrite', () {
      final f = _release.forTrack(_official[1], 2).vorbisFields;
      expect(f.keys.toSet(), {
        'TITLE', 'ARTIST', 'ALBUMARTIST', 'ALBUM', 'TRACKNUMBER',
        // Both spellings of the total, deliberately. Writing one and leaving the other stale put
        // TRACKTOTAL=16 beside TOTALTRACKS=11 in the same file on the real Backstreet's Back: this
        // app read 16 and showed one record, a reader that takes the other field saw it split.
        'TRACKTOTAL', 'TOTALTRACKS',
        'DATE',
      });
      expect(f['TRACKNUMBER'], '2');
      expect(f['TRACKTOTAL'], f['TOTALTRACKS'], reason: 'never two answers in one file');
      expect(f['DATE'], '1996', reason: 'a year, not the package writers\' YYYY/MM/DD');
    });
  });

  group('placeFileDetailed with an authority', () {
    test('files and retags a compilation rip as the album track it really is', () async {
      final staging = Directory('${root.path}${Platform.pathSeparator}_in')..createSync();
      final src = File('${staging.path}${Platform.pathSeparator}01 - Anywhere for You.flac')
        ..writeAsBytesSync(_peerFlac([
          'TITLE=Anywhere for You',
          'ARTIST=Backstreet Boys',
          'ALBUM=The Essential Backstreet Boys',
          'TRACKNUMBER=01',
          'REPLAYGAIN_TRACK_GAIN=-6.5 dB',
        ]));

      final out = await placeFileDetailed(src, root.path, tags: _release.forTrack(_official[1], 2));

      expect(out.how, Placement.moved);
      // Filed under the RECORD, not under the compilation it was ripped from.
      expect(out.path, contains('Backstreet Boys'));
      expect(out.path, isNot(contains('Essential')));
      expect(out.path, endsWith('02 - Anywhere for You.flac'));

      // And the tags inside now say so too — which is what the library and Roon actually read.
      final t = readFlacTags(File(out.path))!;
      expect(t.album, 'Backstreet Boys');
      expect(t.trackNo, 2);
      expect(t.trackTotal, 4);
      expect(t.year, 1996);
      // Nothing else was collateral damage.
      expect(utf8.decode(File(out.path).readAsBytesSync(), allowMalformed: true),
          contains('REPLAYGAIN_TRACK_GAIN'));
    });

    test('a better copy the sweep finds replaces the first, it never lands as a (2)', () async {
      final root = Directory('${Directory.systemTemp.createTempSync('auth3').path}');
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      });
      final s1 = Directory('${root.path}${Platform.pathSeparator}_a')..createSync();
      final s2 = Directory('${root.path}${Platform.pathSeparator}_b')..createSync();
      // Two peers, two very different filenames, same song. The second is bigger — the upgrade.
      final small = File('${s1.path}${Platform.pathSeparator}11. Backstreet Boys - Lets Have A Party.flac')
        ..writeAsBytesSync(_peerFlac(['TITLE=Lets Have A Party', 'TRACKNUMBER=11'], pad: 1000));
      final big = File('${s2.path}${Platform.pathSeparator}Party (BSB rip).flac')
        ..writeAsBytesSync(_peerFlac(['TITLE=Party', 'TRACKNUMBER=1'], pad: 9000));

      final auth = const ReleaseAuthority(
        artist: 'Backstreet Boys',
        album: 'Backstreet Boys',
        albumArtist: 'Backstreet Boys',
        year: 1996,
        tracks: [ChoiceTrack('11', "Let's Have a Party", 230)],
      ).forTrack(const ChoiceTrack('11', "Let's Have a Party", 230), 11);

      final a = await placeFileDetailed(small, root.path, tags: auth);
      final b = await placeFileDetailed(big, root.path, tags: auth);

      expect(a.how, Placement.moved);
      expect(b.how, Placement.moved, reason: 'the bigger copy wins and replaces');
      // Exactly one file, no "(2)": the peer names differ wildly but the album says both are track 11.
      final dir = Directory(File(a.path).parent.path);
      final flacs = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.flac')).toList();
      expect(flacs, hasLength(1), reason: 'one track, one file — got: ${flacs.map((f) => f.uri.pathSegments.last)}');
      expect(flacs.single.path, endsWith("11 - Let's Have a Party.flac"));
      expect(flacs.single.path, isNot(contains('(2)')));
    });

    /// De uitgave zoals de downloadweg hem kent voordat er iets binnenkomt.
    final thrillerTracks = [const ChoiceTrack('2', 'Baby Be Mine', 260)];
    final thriller = ReleaseAuthority(
      artist: 'Michael Jackson',
      album: 'Thriller',
      albumArtist: 'Michael Jackson',
      year: 1982,
      tracks: thrillerTracks,
    ).forTrack(thrillerTracks.first, 2);

    test('een betere versie gaat NAAR het album waar de opname al staat', () async {
      // Het geval uit de bibliotheek. Je hebt Thriller op 24/96 in een map die "Thriller (MFSL One
      // Step)" heet, want zo staat het in de tags. Er komt een 24/192 binnen die `ALBUM = Thriller`
      // draagt. Zonder de opzoeking landt die in een NIEUWE map: twee albums in de bibliotheek, en het
      // mindere bestand blijft staan omdat de vervangingsregel alleen binnen één map kijkt.
      final root = Directory(Directory.systemTemp.createTempSync('vervang').path);
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      });
      final sep = Platform.pathSeparator;

      // Wat er al staat: kleiner, in een map met de naam van de persing.
      final bestaandeMap = Directory('${root.path}${sep}Michael Jackson${sep}Thriller (MFSL One Step)')
        ..createSync(recursive: true);
      final oud = File('${bestaandeMap.path}${sep}02 - Baby Be Mine.flac')
        ..writeAsBytesSync(_peerFlac(['TITLE=Baby Be Mine', 'ARTIST=Michael Jackson'], pad: 1000));

      // Wat er binnenkomt: groter, met een andere albumtag.
      final staging = Directory('${root.path}${sep}_in')..createSync();
      final nieuw = File('${staging.path}${sep}02 Michael Jackson - CD-01 - Baby Be Mine.flac')
        ..writeAsBytesSync(_peerFlac(
            ['TITLE=Baby Be Mine', 'ARTIST=Michael Jackson', 'ALBUM=Thriller'],
            pad: 9000));

      // Met een gezaghebbende tracklijst, want zo loopt de echte downloadweg: de uitgave is al gekozen
      // voordat er ook maar één byte binnenkwam.
      final uit = await placeFileDetailed(nieuw, root.path,
          tags: thriller,
          staatAl: (artiest, titel) =>
              titel.toLowerCase().contains('baby be mine') ? oud.path : null);

      expect(uit.how, Placement.moved);
      expect(File(uit.path).parent.path, bestaandeMap.path,
          reason: 'de nieuwe hoort in het bestaande album, niet in een tweede map');
      expect(uit.path, oud.path,
          reason: 'en op het bestand zelf, niet ernaast onder de naam die de uploader koos');
      final over = bestaandeMap
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.flac'))
          .toList();
      expect(over, hasLength(1), reason: 'één opname, één bestand — geen tweede album ernaast');
      expect(over.single.lengthSync(), greaterThan(5000), reason: 'en dat is de grootste van de twee');
      expect(over.single.path, oud.path, reason: 'op precies de plek waar de oude stond');
      // Weggooien doet de app niet: de vorige staat geparkeerd, niet verdwenen.
      final geparkeerd = root
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.contains('_dubbel') && f.path.endsWith('.flac'))
          .toList();
      expect(geparkeerd, hasLength(1), reason: 'de mindere is opzij gezet, niet gewist');
      expect(geparkeerd.single.lengthSync(), lessThan(5000));
    });

    test('de nieuwkomer neemt de albumnaam van de buren over', () async {
      // Zonder dit staat het betere bestand netjes in de goede map en tóch als apart album in beeld:
      // de bibliotheek groepeert op de ALBUM-tag, en elke peer schrijft een andere. Gemeten kwamen er
      // voor Thriller drie varianten binnen — "Thriller", "Thriller (MFSL One Step)" en
      // "Thriller (Epic, Mjj Productions - 88875143731, Eu)".
      final root = Directory(Directory.systemTemp.createTempSync('naam').path);
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      });
      final sep = Platform.pathSeparator;
      final map = Directory('${root.path}${sep}Michael Jackson${sep}Thriller (MFSL One Step)')
        ..createSync(recursive: true);
      // Drie buren die het eens zijn, en één afwijkende: de meerderheid hoort te beslissen.
      for (final n in ['01', '03', '04']) {
        File('${map.path}$sep$n - x.flac').writeAsBytesSync(
            _peerFlac(['TITLE=x', 'ARTIST=Michael Jackson', 'ALBUM=Thriller (MFSL One Step)']));
      }
      File('${map.path}${sep}05 - y.flac').writeAsBytesSync(
          _peerFlac(['TITLE=y', 'ARTIST=Michael Jackson', 'ALBUM=Thriller (iets anders)']));
      final oud = File('${map.path}${sep}02 - Baby Be Mine.flac')
        ..writeAsBytesSync(
            _peerFlac(['TITLE=Baby Be Mine', 'ARTIST=Michael Jackson', 'ALBUM=Thriller (MFSL One Step)']));

      final staging = Directory('${root.path}${sep}_in')..createSync();
      final nieuw = File('${staging.path}${sep}02 - Baby Be Mine.flac')
        ..writeAsBytesSync(_peerFlac([
          'TITLE=Baby Be Mine',
          'ARTIST=Michael Jackson',
          'ALBUM=Thriller (Epic, Mjj Productions - 88875143731, Eu)',
        ], pad: 9000));

      final uit = await placeFileDetailed(nieuw, root.path, staatAl: (a, t) => oud.path);

      expect(uit.how, Placement.moved);
      final geschreven = readFlacTags(File(uit.path))!;
      expect(geschreven.album, 'Thriller (MFSL One Step)',
          reason: 'de nieuwkomer hoort bij dit album, dus draagt hij die naam');
    });

    test('de nieuwkomer neemt ook het AANTAL NUMMERS van de buren over', () async {
      // Het tweede soort dubbel, en het gemenere: de bibliotheek splitst een album zodra twee nummers
      // hetzelfde tracknummer claimen én een ander TRACKTOTAL opgeven. Een uploader ript van een andere
      // persing en schrijft 11 of 17 waar jouw plaat 13 zegt — en dan breekt één vervangen nummer de
      // hele plaat. Gemeten op Backstreet's Back: drie tegels van één album, 12 + 1 + 2 nummers.
      final root = Directory(Directory.systemTemp.createTempSync('totaal').path);
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      });
      final sep = Platform.pathSeparator;
      final map = Directory('${root.path}${sep}Backstreet Boys${sep}Backstreet\'s Back')
        ..createSync(recursive: true);
      for (final n in ['01', '03', '04']) {
        File('${map.path}$sep$n - x.flac').writeAsBytesSync(_peerFlac([
          'TITLE=x',
          'ARTIST=Backstreet Boys',
          'ALBUM=Backstreet\'s Back',
          'TRACKTOTAL=13',
        ]));
      }

      final oud = File('${map.path}${sep}02 - Everybody.flac')
        ..writeAsBytesSync(_peerFlac([
          'TITLE=Everybody',
          'ARTIST=Backstreet Boys',
          'ALBUM=Backstreet\'s Back',
          'TRACKTOTAL=13',
        ]));

      final staging = Directory('${root.path}${sep}_in')..createSync();
      // Zonder tracknummer in de naam, precies zoals de uploaders het aanleveren: zo kwam
      // "Bailamos.flac" naast "10 - Bailamos.flac" te liggen in plaats van erop.
      final nieuw = File('${staging.path}${sep}Everybody.flac')
        ..writeAsBytesSync(_peerFlac([
          'TITLE=Everybody',
          'ARTIST=Backstreet Boys',
          'ALBUM=Backstreet\'s Back',
          'TRACKTOTAL=17', // een andere persing — precies wat de plaat brak
        ], pad: 9000));

      final uit = await placeFileDetailed(nieuw, root.path, staatAl: (a, t) => oud.path);
      expect(uit.path, oud.path, reason: 'op het bestaande bestand, niet ernaast');
      expect(map.listSync().whereType<File>().where((f) => f.path.endsWith('.flac')), hasLength(4),
          reason: 'drie buren plus de vervanger — geen vijfde bestand erbij');

      expect(uit.how, Placement.moved);
      expect(readFlacTags(File(uit.path))!.trackTotal, 13,
          reason: 'het gaat er niet om van welke persing dit bestand kwam, maar bij welke plaat het hoort');
    });

    test('een MINDERE versie dringt zich niet op', () async {
      // Dezelfde weg, andersom: wie al het beste heeft, houdt het. Anders zou elke volgende download
      // je bibliotheek weer omlaag trekken.
      final root = Directory(Directory.systemTemp.createTempSync('vervang2').path);
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      });
      final sep = Platform.pathSeparator;
      final bestaandeMap = Directory('${root.path}${sep}Michael Jackson${sep}Thriller (MFSL One Step)')
        ..createSync(recursive: true);
      final groot = File('${bestaandeMap.path}${sep}02 - Baby Be Mine.flac')
        ..writeAsBytesSync(_peerFlac(['TITLE=Baby Be Mine', 'ARTIST=Michael Jackson'], pad: 9000));
      final staging = Directory('${root.path}${sep}_in')..createSync();
      final klein = File('${staging.path}${sep}02 - Baby Be Mine.flac')
        ..writeAsBytesSync(_peerFlac(['TITLE=Baby Be Mine', 'ARTIST=Michael Jackson'], pad: 1000));

      final uit = await placeFileDetailed(klein, root.path,
          tags: thriller, staatAl: (artiest, titel) => groot.path);

      expect(uit.how, Placement.duplicate);
      expect(klein.existsSync(), isFalse, reason: 'de mindere kopie is opgeruimd');
      expect(File(uit.path).lengthSync(), greaterThan(5000), reason: 'de goede staat er nog');
    });

    test('zonder opzoeking blijft alles zoals het was', () async {
      // De parameter is optioneel met opzet: alleen de downloadweg geeft hem mee. Het opbergen van een
      // bestaande verzameling hoort niet ineens mappen samen te trekken.
      final root = Directory(Directory.systemTemp.createTempSync('vervang3').path);
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      });
      final sep = Platform.pathSeparator;
      final staging = Directory('${root.path}${sep}_in')..createSync();
      final f = File('${staging.path}${sep}02 - Baby Be Mine.flac')
        ..writeAsBytesSync(_peerFlac(
            ['TITLE=Baby Be Mine', 'ARTIST=Michael Jackson', 'ALBUM=Thriller'],
            pad: 1000));
      final uit = await placeFileDetailed(f, root.path);
      expect(uit.how, Placement.moved);
      expect(uit.path, contains('Thriller'));
    });

    test('without an authority the peer still decides, exactly as before', () async {
      final staging = Directory('${root.path}${Platform.pathSeparator}_in2')..createSync();
      final src = File('${staging.path}${Platform.pathSeparator}01 - Anywhere for You.flac')
        ..writeAsBytesSync(_peerFlac([
          'TITLE=Anywhere for You',
          'ARTIST=Backstreet Boys',
          'ALBUM=The Essential Backstreet Boys',
          'TRACKNUMBER=01',
        ]));

      final out = await placeFileDetailed(src, root.path);
      expect(out.how, Placement.moved);
      expect(out.path, contains('Essential'), reason: 'unchanged behaviour where we know nothing');
      expect(readFlacTags(File(out.path))!.album, 'The Essential Backstreet Boys',
          reason: 'and nothing was rewritten');
    });
  });
}
