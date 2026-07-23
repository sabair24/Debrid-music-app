import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/flac_tags.dart';

/// Build a minimal but structurally valid FLAC: STREAMINFO, VORBIS_COMMENT, a PADDING block, then
/// some "audio". Enough to prove the writer preserves what it must.
Uint8List _flac({
  required List<String> comments,
  String vendor = 'reference libFLAC 1.3.2',
  bool withComments = true,
  List<int>? audio,
}) {
  final out = BytesBuilder();
  out.add(ascii.encode('fLaC'));

  void block(int type, List<int> body, bool last) {
    out.add([(last ? 0x80 : 0) | type, (body.length >> 16) & 0xFF, (body.length >> 8) & 0xFF, body.length & 0xFF]);
    out.add(body);
  }

  // STREAMINFO: 34 bytes. Sample rate 44100, 2 channels, some sample count.
  final si = Uint8List(34);
  const rate = 44100;
  si[10] = (rate >> 12) & 0xFF;
  si[11] = (rate >> 4) & 0xFF;
  si[12] = ((rate & 0x0F) << 4) | (1 << 1); // channels-1 = 1
  si[13] = 0;
  si[14] = 0x02; // ~ a few seconds of samples
  si[15] = 0;
  si[16] = 0;
  si[17] = 0;
  block(0, si, false);

  if (withComments) {
    final b = BytesBuilder();
    void u32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
    final ven = utf8.encode(vendor);
    u32(ven.length);
    b.add(ven);
    u32(comments.length);
    for (final c in comments) {
      final e = utf8.encode(c);
      u32(e.length);
      b.add(e);
    }
    block(4, b.toBytes(), false);
  }

  block(1, List.filled(64, 0), true); // PADDING, last
  out.add(audio ?? List.filled(4096, 0x7F));
  return out.toBytes();
}

Map<String, String> _readComments(File f) {
  final b = f.readAsBytesSync();
  var i = 4;
  final out = <String, String>{};
  while (true) {
    final last = (b[i] & 0x80) != 0;
    final type = b[i] & 0x7F;
    final len = (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    i += 4;
    if (type == 4) {
      var j = i;
      int u32() {
        final v = b[j] | (b[j + 1] << 8) | (b[j + 2] << 16) | (b[j + 3] << 24);
        j += 4;
        return v;
      }

      final vl = u32();
      out['__vendor'] = utf8.decode(b.sublist(j, j + vl));
      j += vl;
      final n = u32();
      for (var k = 0; k < n; k++) {
        final l = u32();
        final e = utf8.decode(b.sublist(j, j + l));
        j += l;
        final eq = e.indexOf('=');
        out[e.substring(0, eq)] = e.substring(eq + 1);
      }
    }
    i += len;
    if (last) break;
  }
  out['__audio'] = b.sublist(i).length.toString();
  return out;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('flacw'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  File _write(Uint8List bytes, [String name = 'a.flac']) =>
      File('${dir.path}${Platform.pathSeparator}$name')..writeAsBytesSync(bytes);

  test('replaces only what it is asked to, and keeps everything else', () {
    final f = _write(_flac(comments: [
      'TITLE=Anywhere For You',
      'ARTIST=Backstreet Boys',
      'ALBUM=The Essential Backstreet Boys',
      'TRACKNUMBER=01',
      'REPLAYGAIN_TRACK_GAIN=-7.34 dB',
      'MUSICBRAINZ_ALBUMID=abc-123',
      'MY_OWN_WEIRD_TAG=keep me',
    ]));

    final ok = writeFlacFields(f, {
      'TITLE': 'Anywhere for You',
      'ALBUM': 'Backstreet Boys',
      'ALBUMARTIST': 'Backstreet Boys',
      'TRACKNUMBER': '2',
      'TRACKTOTAL': '13',
      'DATE': '1996',
    });
    expect(ok, isTrue);

    final got = _readComments(f);
    expect(got['TITLE'], 'Anywhere for You');
    expect(got['ALBUM'], 'Backstreet Boys');
    expect(got['ALBUMARTIST'], 'Backstreet Boys');
    expect(got['TRACKNUMBER'], '2');
    expect(got['TRACKTOTAL'], '13');
    expect(got['DATE'], '1996');
    // The whole point: none of this may be collateral damage.
    expect(got['ARTIST'], 'Backstreet Boys', reason: 'untouched field survives');
    expect(got['REPLAYGAIN_TRACK_GAIN'], '-7.34 dB');
    expect(got['MUSICBRAINZ_ALBUMID'], 'abc-123');
    expect(got['MY_OWN_WEIRD_TAG'], 'keep me');
    expect(got['__vendor'], 'reference libFLAC 1.3.2', reason: 'vendor string is not ours to erase');
    expect(got['__audio'], '4096', reason: 'not one audio byte moved');
  });

  test('the old value is replaced, not duplicated', () {
    final f = _write(_flac(comments: ['TRACKNUMBER=03/12', 'TITLE=x']));
    writeFlacFields(f, {'TRACKNUMBER': '2', 'TRACKTOTAL': '13'});
    final b = f.readAsBytesSync();
    // "03/12" must be gone from the file entirely.
    expect(utf8.decode(b, allowMalformed: true).contains('03/12'), isFalse);
    expect(_readComments(f)['TRACKNUMBER'], '2');
  });

  test('case-insensitive keys, written back in the conventional case', () {
    final f = _write(_flac(comments: ['TrackNumber=9', 'Title=old']));
    writeFlacFields(f, {'TRACKNUMBER': '2', 'TITLE': 'new'});
    final got = _readComments(f);
    expect(got['TRACKNUMBER'], '2');
    expect(got['TITLE'], 'new');
    expect(got.containsKey('TrackNumber'), isFalse, reason: 'no second copy under another spelling');
  });

  test('a null value removes a field', () {
    final f = _write(_flac(comments: ['TITLE=x', 'COMMENT=ripped by someone']));
    writeFlacFields(f, {'COMMENT': null});
    expect(_readComments(f).containsKey('COMMENT'), isFalse);
    expect(_readComments(f)['TITLE'], 'x');
  });

  test('adds a comment block to a file that has none', () {
    final f = _write(_flac(comments: const [], withComments: false));
    expect(writeFlacFields(f, {'TITLE': 'new', 'TRACKNUMBER': '1'}), isTrue);
    final got = _readComments(f);
    expect(got['TITLE'], 'new');
    expect(got['__audio'], '4096');
  });

  test('a vinyl A3 and a slashed number survive being read back', () {
    final f = _write(_flac(comments: ['TRACKNUMBER=A3', 'TITLE=side a three']));
    expect(writeFlacFields(f, {'ALBUM': 'X'}), isTrue);
    // The reader still copes, which is why this parser exists at all.
    final t = readFlacTags(f);
    expect(t, isNotNull);
    expect(t!.trackNo, 3);
    expect(t.album, 'X');
  });

  test('what it cannot rewrite safely, it leaves alone', () {
    // Not a FLAC.
    final f = _write(Uint8List.fromList(ascii.encode('ID3 this is an mp3')));
    final before = f.readAsBytesSync();
    expect(writeFlacFields(f, {'TITLE': 'x'}), isFalse);
    expect(f.readAsBytesSync(), before, reason: 'untouched');

    // Truncated mid-block.
    final t = _write(_flac(comments: ['TITLE=x']).sublist(0, 20), 'b.flac');
    final beforeT = t.readAsBytesSync();
    expect(writeFlacFields(t, {'TITLE': 'y'}), isFalse);
    expect(t.readAsBytesSync(), beforeT);
  });

  test('an empty request changes nothing', () {
    final f = _write(_flac(comments: ['TITLE=x']));
    final before = f.readAsBytesSync();
    expect(writeFlacFields(f, const {}), isFalse);
    expect(f.readAsBytesSync(), before);
  });

  test('no .tags leftover is ever left behind', () {
    final f = _write(_flac(comments: ['TITLE=x']));
    writeFlacFields(f, {'TITLE': 'y'});
    expect(File('${f.path}.tags').existsSync(), isFalse);
    expect(dir.listSync().length, 1);
  });

  test('round-trips through the app reader', () {
    final f = _write(_flac(comments: ['TITLE=wrong', 'ARTIST=wrong', 'ALBUM=wrong', 'TRACKNUMBER=19']));
    writeFlacFields(f, {
      'TITLE': 'Anywhere for You',
      'ARTIST': 'Backstreet Boys',
      'ALBUM': 'Backstreet Boys',
      'TRACKNUMBER': '2',
      'TRACKTOTAL': '13',
      'DATE': '1996',
    });
    final t = readFlacTags(f)!;
    expect(t.title, 'Anywhere for You');
    expect(t.artist, 'Backstreet Boys');
    expect(t.album, 'Backstreet Boys');
    expect(t.trackNo, 2);
    expect(t.trackTotal, 13);
    expect(t.year, 1996);
    expect(t.duration, isNotNull, reason: 'STREAMINFO came through intact');
  });
}
