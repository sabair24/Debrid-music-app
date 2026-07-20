import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/organize.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal valid FLAC header: STREAMINFO (for the duration) + VORBIS_COMMENT, no audio.
Uint8List buildFlac(List<String> comments, {int seconds = 240, int sampleRate = 44100}) {
  final b = BytesBuilder();
  b.add(ascii.encode('fLaC'));
  b.add([0x00, 0x00, 0x00, 0x22]);
  final total = seconds * sampleRate;
  final si = Uint8List(34);
  si[10] = (sampleRate >> 12) & 0xFF;
  si[11] = (sampleRate >> 4) & 0xFF;
  si[12] = (sampleRate & 0x0F) << 4;
  si[13] = (total >> 32) & 0x0F;
  si[14] = (total >> 24) & 0xFF;
  si[15] = (total >> 16) & 0xFF;
  si[16] = (total >> 8) & 0xFF;
  si[17] = total & 0xFF;
  b.add(si);

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

const _tags = ['TITLE=D.A.N.C.E.', 'ARTIST=Justice', 'ALBUM=Cross', 'TRACKNUMBER=3'];

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('place_test'));
  tearDown(() {
    // Best-effort: a file that reaches audio_metadata_reader's throwing path leaves a handle open
    // (the very leak that made downloads unmovable), so Windows can refuse the delete here.
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  File staged(String name, Uint8List bytes) {
    final d = Directory('${root.path}${Platform.pathSeparator}_inkomend')..createSync(recursive: true);
    final f = File('${d.path}${Platform.pathSeparator}$name');
    f.writeAsBytesSync(bytes);
    return f;
  }

  test('files a track into the tidy tree', () async {
    final f = staged('x.flac', buildFlac(_tags));
    final out = await placeFileDetailed(f, root.path);
    expect(out.how, Placement.moved);
    expect(out.path, endsWith('Albums${Platform.pathSeparator}Justice${Platform.pathSeparator}Cross'
        '${Platform.pathSeparator}03 - D.A.N.C.E..flac'));
    expect(f.existsSync(), isFalse);
    expect(File(out.path).existsSync(), isTrue);
  });

  test('the same recording downloaded twice is reported as a duplicate, not a fresh success', () async {
    await placeFileDetailed(staged('a.flac', buildFlac(_tags, seconds: 240)), root.path);
    final second = staged('b.flac', buildFlac(_tags, seconds: 240));
    final out = await placeFileDetailed(second, root.path);
    expect(out.how, Placement.duplicate);
    expect(second.existsSync(), isFalse); // the loser is dropped
  });

  test('a different take with identical tags is KEPT, not discarded', () async {
    // Exactly the case that silently ate a download: a live version whose version marker never
    // made it into the title tag, so it resolves to the same destination as the studio cut.
    final first = await placeFileDetailed(staged('studio.flac', buildFlac(_tags, seconds: 240)), root.path);
    final live = staged('live.flac', buildFlac(_tags, seconds: 358));
    final out = await placeFileDetailed(live, root.path);
    expect(out.how, Placement.moved);
    expect(out.path, isNot(first.path));
    expect(out.path, contains('(2)'));
    expect(File(first.path).existsSync(), isTrue); // both survive
    expect(File(out.path).existsSync(), isTrue);
  });

  test('a slightly different length still counts as the same recording', () async {
    await placeFileDetailed(staged('a.flac', buildFlac(_tags, seconds: 240)), root.path);
    final out = await placeFileDetailed(staged('b.flac', buildFlac(_tags, seconds: 242)), root.path);
    expect(out.how, Placement.duplicate);
  });

  test('an unreadable file is reported as stuck and left where it is', () async {
    final f = staged('junk.flac', Uint8List.fromList(utf8.encode('not a flac')));
    final out = await placeFileDetailed(f, root.path);
    expect(out.how, Placement.stuck);
    expect(out.path, f.path);
    expect(f.existsSync(), isTrue); // never lose the download
  });
}
