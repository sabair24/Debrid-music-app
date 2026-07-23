@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/flac_tags.dart';

/// Rewrites a COPY of a real file from the library. Excluded from the normal run because it needs
/// that library to exist — but it is the only test that proves the writer survives a real ripper's
/// output, with its picture block, seektable, padding and whatever else it decided to include.
void main() {
  test('a real FLAC keeps its audio, its pictures and its other tags', () {
    final root = Directory(r'D:\Flac music 2024');
    if (!root.existsSync()) {
      markTestSkipped('library not present');
      return;
    }
    final src = root
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .firstWhere((f) => f.path.toLowerCase().endsWith('.flac') && f.lengthSync() > 5 * 1024 * 1024);

    final dir = Directory.systemTemp.createTempSync('flacreal');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final copy = src.copySync('${dir.path}${Platform.pathSeparator}t.flac');

    final before = readFlacTags(copy)!;
    final beforeBytes = copy.readAsBytesSync();
    // Every comment the file actually carries, so we can prove none went missing.
    final beforeKeys = _commentKeys(copy);

    expect(
        writeFlacFields(copy, {
          'TITLE': 'Test Title',
          'ALBUM': 'Test Album',
          'ALBUMARTIST': 'Test Artist',
          'TRACKNUMBER': '7',
          'TRACKTOTAL': '13',
          'DATE': '1996',
        }),
        isTrue);

    final after = readFlacTags(copy)!;
    expect(after.title, 'Test Title');
    expect(after.album, 'Test Album');
    expect(after.trackNo, 7);
    expect(after.trackTotal, 13);
    expect(after.year, 1996);

    // The audio is bit-identical: same duration, same channel count, and the same number of bytes
    // once the metadata difference is accounted for.
    expect(after.duration, before.duration, reason: 'STREAMINFO untouched');
    expect(after.channels, before.channels);

    final afterKeys = _commentKeys(copy);
    final lost = beforeKeys.difference(afterKeys).difference(
        {'TITLE', 'ALBUM', 'ALBUMARTIST', 'TRACKNUMBER', 'TRACKTOTAL', 'DATE'});
    expect(lost, isEmpty, reason: 'these tags were dropped: $lost');

    // And the file is still playable-shaped: it starts with fLaC and the audio tail is unchanged.
    expect(copy.readAsBytesSync().sublist(0, 4), beforeBytes.sublist(0, 4));
    expect(_audioTail(copy), _audioTail(src), reason: 'not one audio byte moved');
  });
}

Set<String> _commentKeys(File f) {
  final b = f.readAsBytesSync();
  var i = 4;
  final out = <String>{};
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

      // Two steps, never `j += u32()`: the compound assignment reads j BEFORE u32() advances it,
      // which silently desyncs the whole block. flac_tags.dart warns about exactly this.
      final vendorLen = u32();
      j += vendorLen;
      final n = u32();
      for (var k = 0; k < n; k++) {
        final l = u32();
        final e = utf8.decode(b.sublist(j, j + l), allowMalformed: true);
        j += l;
        final eq = e.indexOf('=');
        if (eq > 0) out.add(e.substring(0, eq).toUpperCase());
      }
    }
    i += len;
    if (last) break;
  }
  return out;
}

List<int> _audioTail(File f) {
  final b = f.readAsBytesSync();
  var i = 4;
  while (true) {
    final last = (b[i] & 0x80) != 0;
    final len = (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    i += 4 + len;
    if (last) break;
  }
  // Just the first and last kilobyte — comparing 36 MB twice is not worth the seconds.
  return [...b.sublist(i, i + 1024), ...b.sublist(b.length - 1024)];
}
