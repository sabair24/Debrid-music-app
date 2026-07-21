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

  test('the filename outweighs the duration: a live take of equal length is still kept', () async {
    // The real case: the studio cut runs 4:03 and the "(Live Version)" 4:02, so duration alone
    // called them the same recording and the download was silently discarded.
    final studio = await placeFileDetailed(staged('03 - D.A.N.C.E..flac', buildFlac(_tags, seconds: 243)), root.path);
    final live = staged('08 - D.A.N.C.E. (Live Version).flac', buildFlac(_tags, seconds: 242));
    final out = await placeFileDetailed(live, root.path);
    expect(out.how, Placement.moved);
    expect(File(studio.path).existsSync(), isTrue);
    expect(File(out.path).existsSync(), isTrue);
    // The marker is carried into the filed name, so it stays obvious which take this is.
    expect(out.path, endsWith('03 - D.A.N.C.E. (live version).flac'));
    expect(studio.path, endsWith('03 - D.A.N.C.E..flac'));
  });

  test('the same version marker on both sides still dedups', () async {
    await placeFileDetailed(staged('a (Live Version).flac', buildFlac(_tags, seconds: 242)), root.path);
    final out = await placeFileDetailed(staged('b (live version).flac', buildFlac(_tags, seconds: 242)), root.path);
    expect(out.how, Placement.duplicate);
  });

  test('bracketed noise is not mistaken for a version', () {
    expect(versionMarkers('01 - D.A.N.C.E. (2021) [PMEDIA] (WWW).flac'), isEmpty);
    expect(versionMarkers('08 - D.A.N.C.E. (Live Version).flac'), {'live version'});
    expect(versionMarkers('04 - D.A.N.C.E. (Alan Braxe & Fred Falke Remix).flac'),
        {'alan braxe & fred falke remix'});
    expect(versionMarkers('06 - D.A.N.C.E Part 2.flac'), {'part 2'});
  });

  group('upgrading a track replaces the copy it supersedes', () {
    // The destination name carries the source's extension, so a FLAC upgrade lands on a different
    // path than the MP3 it replaces — without matching across formats both would stay forever.
    File placeMp3(String name) {
      final dir = Directory('${root.path}${Platform.pathSeparator}Albums${Platform.pathSeparator}Justice'
          '${Platform.pathSeparator}Cross')
        ..createSync(recursive: true);
      final f = File('${dir.path}${Platform.pathSeparator}$name');
      f.writeAsBytesSync(Uint8List(4000)); // small: the FLAC must win on format, not size
      return f;
    }

    test('a better FLAC removes the MP3 already filed', () async {
      final mp3 = placeMp3('03 - D.A.N.C.E..mp3');
      final out = await placeFileDetailed(staged('x.flac', buildFlac(_tags)), root.path);
      expect(out.how, Placement.moved);
      expect(out.path, endsWith('.flac'));
      expect(mp3.existsSync(), isFalse, reason: 'the superseded MP3 must be gone');
      expect(File(out.path).existsSync(), isTrue);
    });

    test('a differing disc prefix still counts as the same track', () async {
      final mp3 = placeMp3('1-03. D.A.N.C.E..mp3');
      final out = await placeFileDetailed(staged('x.flac', buildFlac(_tags)), root.path);
      expect(out.how, Placement.moved);
      expect(mp3.existsSync(), isFalse);
    });

    test('a WORSE copy is dropped rather than replacing the good one', () async {
      final flac = await placeFileDetailed(staged('good.flac', buildFlac(_tags)), root.path);
      // An MP3 arriving afterwards must not evict the FLAC.
      final dir = Directory(flac.path.substring(0, flac.path.lastIndexOf(Platform.pathSeparator)));
      final mp3src = File('${root.path}${Platform.pathSeparator}_inkomend${Platform.pathSeparator}late.mp3');
      mp3src.parent.createSync(recursive: true);
      mp3src.writeAsBytesSync(Uint8List(9999999));
      final out = await placeFileDetailed(mp3src, root.path, tags: readTags(File(flac.path)));
      expect(out.how, Placement.duplicate);
      expect(File(flac.path).existsSync(), isTrue, reason: 'the FLAC must survive');
      expect(dir.listSync().whereType<File>().length, 1);
    });

    test('a different track in the same folder is left alone', () async {
      final other = placeMp3('04 - Phantom.mp3');
      await placeFileDetailed(staged('x.flac', buildFlac(_tags)), root.path);
      expect(other.existsSync(), isTrue);
    });

    test('a number that belongs to the TITLE is not mistaken for a track number', () async {
      // Regression: the prefix regex used to eat the title's leading digits, so
      // "10 - 99 Problems.mp3" collapsed to "problems" and was deleted to make room for an
      // unrelated "05 - Problems.flac".
      final dir = Directory('${root.path}${Platform.pathSeparator}Albums${Platform.pathSeparator}Justice'
          '${Platform.pathSeparator}Cross')
        ..createSync(recursive: true);
      final other = File('${dir.path}${Platform.pathSeparator}10 - 99 Problems.mp3')
        ..writeAsBytesSync(Uint8List(4000));
      final out = await placeFileDetailed(
          staged('x.flac', buildFlac(['TITLE=Problems', 'ARTIST=Justice', 'ALBUM=Cross', 'TRACKNUMBER=5'])),
          root.path);
      expect(out.how, Placement.moved);
      expect(other.existsSync(), isTrue, reason: '99 Problems is a different song and must survive');
    });

    test('two discs repeating a title in the SAME format are both kept', () async {
      // A bonus disc often repeats a title. Same extension on both sides is never a cross-format
      // upgrade, so neither may be removed when a third, different track is filed.
      final disc1 = placeMp3('1-05 - D.A.N.C.E..mp3');
      final disc2 = placeMp3('2-05 - D.A.N.C.E..mp3');
      await placeFileDetailed(
          staged('x.flac', buildFlac(['TITLE=Phantom', 'ARTIST=Justice', 'ALBUM=Cross', 'TRACKNUMBER=7'])),
          root.path);
      expect(disc1.existsSync(), isTrue);
      expect(disc2.existsSync(), isTrue);
    });

    test('the superseded copy is only removed once the new one is in place', () async {
      final mp3 = placeMp3('03 - D.A.N.C.E..mp3');
      final out = await placeFileDetailed(staged('x.flac', buildFlac(_tags)), root.path);
      expect(File(out.path).existsSync(), isTrue);
      expect(mp3.existsSync(), isFalse);
      // No leftover staging artefact from the two-step install.
      expect(Directory(out.path.substring(0, out.path.lastIndexOf(Platform.pathSeparator)))
          .listSync()
          .where((e) => e.path.endsWith('.incoming'))
          .isEmpty,
          isTrue);
    });
  });

  test('an unreadable file is reported as stuck and left where it is', () async {
    final f = staged('junk.flac', Uint8List.fromList(utf8.encode('not a flac')));
    final out = await placeFileDetailed(f, root.path);
    expect(out.how, Placement.stuck);
    expect(out.path, f.path);
    expect(f.existsSync(), isTrue); // never lose the download
  });
}
