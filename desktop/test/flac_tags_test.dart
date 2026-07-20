import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/flac_tags.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal but valid FLAC header: STREAMINFO + VORBIS_COMMENT, no audio.
Uint8List buildFlac(List<String> comments, {int sampleRate = 44100, int totalSamples = 441000}) {
  final b = BytesBuilder();
  b.add(ascii.encode('fLaC'));

  // STREAMINFO (type 0, 34 bytes). Only the sample-rate/total-samples packing matters here.
  b.add([0x00, 0x00, 0x00, 0x22]);
  final si = Uint8List(34);
  si[10] = (sampleRate >> 12) & 0xFF;
  si[11] = (sampleRate >> 4) & 0xFF;
  si[12] = (sampleRate & 0x0F) << 4;
  si[13] = (totalSamples >> 32) & 0x0F;
  si[14] = (totalSamples >> 24) & 0xFF;
  si[15] = (totalSamples >> 16) & 0xFF;
  si[16] = (totalSamples >> 8) & 0xFF;
  si[17] = totalSamples & 0xFF;
  b.add(si);

  // VORBIS_COMMENT (type 4), flagged as the last block.
  final v = BytesBuilder();
  final vendor = utf8.encode('test');
  v.add(_le32(vendor.length));
  v.add(vendor);
  v.add(_le32(comments.length));
  for (final c in comments) {
    final bytes = utf8.encode(c);
    v.add(_le32(bytes.length));
    v.add(bytes);
  }
  final vb = v.takeBytes();
  b.add([0x84, (vb.length >> 16) & 0xFF, (vb.length >> 8) & 0xFF, vb.length & 0xFF]);
  b.add(vb);
  return b.takeBytes();
}

List<int> _le32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

File writeTemp(Uint8List bytes, String name) {
  final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}$name');
  f.writeAsBytesSync(bytes);
  return f;
}

void main() {
  test('reads ordinary tags', () {
    final f = writeTemp(
        buildFlac(['TITLE=D.A.N.C.E.', 'ARTIST=Justice', 'ALBUM=Cross', 'TRACKNUMBER=3', 'DATE=2007']),
        'flac_ok.flac');
    final t = readFlacTags(f)!;
    expect(t.title, 'D.A.N.C.E.');
    expect(t.artist, 'Justice');
    expect(t.album, 'Cross');
    expect(t.trackNo, 3);
    expect(t.year, 2007);
    expect(t.duration, const Duration(seconds: 10));
    f.deleteSync();
  });

  test('tolerates a vinyl track number — the case that broke the parser package', () {
    final f = writeTemp(buildFlac(['TITLE=D.A.N.C.E.', 'ARTIST=Justice', 'TRACKNUMBER=A3']), 'flac_vinyl.flac');
    final t = readFlacTags(f)!;
    expect(t.trackNo, 3);
    expect(t.title, 'D.A.N.C.E.');
    f.deleteSync();
  });

  test('handles "3/12" track numbers and non-ASCII tags', () {
    final f = writeTemp(buildFlac(['TITLE=Genesis', 'ALBUM=†', 'TRACKNUMBER=3/12']), 'flac_utf8.flac');
    final t = readFlacTags(f)!;
    expect(t.album, '†'); // read as UTF-8, not as raw code units
    expect(t.trackNo, 3);
    f.deleteSync();
  });

  test('missing fields stay null rather than becoming empty strings', () {
    final f = writeTemp(buildFlac(['TITLE=Solo']), 'flac_sparse.flac');
    final t = readFlacTags(f)!;
    expect(t.title, 'Solo');
    expect(t.artist, isNull);
    expect(t.album, isNull);
    expect(t.trackNo, 0);
    f.deleteSync();
  });

  test('falls back to ALBUMARTIST when ARTIST is absent', () {
    final f = writeTemp(buildFlac(['TITLE=X', 'ALBUMARTIST=Justice']), 'flac_aa.flac');
    expect(readFlacTags(f)!.artist, 'Justice');
    f.deleteSync();
  });

  test('returns null for a non-FLAC file instead of throwing', () {
    final f = writeTemp(Uint8List.fromList(utf8.encode('not a flac file at all')), 'flac_bogus.flac');
    expect(readFlacTags(f), isNull);
    f.deleteSync();
  });

  test('returns null for a truncated header instead of throwing', () {
    final full = buildFlac(['TITLE=X', 'ARTIST=Y']);
    final f = writeTemp(Uint8List.sublistView(full, 0, 12), 'flac_trunc.flac');
    expect(() => readFlacTags(f), returnsNormally);
    f.deleteSync();
  });
}
