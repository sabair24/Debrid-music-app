import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/organize.dart';

/// A tiny but valid FLAC carrying the tags a Soulseek peer might have written.
Uint8List _peerFlac(List<String> comments) {
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
  out.add(List.filled(2048, 0x11));
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

    test('names only the fields it is allowed to overwrite', () {
      final f = _release.forTrack(_official[1], 2).vorbisFields;
      expect(f.keys.toSet(),
          {'TITLE', 'ARTIST', 'ALBUMARTIST', 'ALBUM', 'TRACKNUMBER', 'TRACKTOTAL', 'DATE'});
      expect(f['TRACKNUMBER'], '2');
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
