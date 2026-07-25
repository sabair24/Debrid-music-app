/// The library, browsable with the PC off.
///
/// Round-trips a real [CatalogSnapshot] through a fake Firestore and back into a real
/// [LibraryStore], because the promise is that the copy shows the SAME albums and pressings the PC
/// serves — not a simplified version of them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/cloud/catalog_mirror.dart';
import 'package:debridmusic/cloud/firestore.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';

/// A Firestore that lives in a map. Counts reads and writes, because the whole design of the
/// mirror is about not doing many of either.
class FakeDb implements Firestore {
  final Map<String, Map<String, dynamic>> docs = {};
  int reads = 0, writes = 0;

  @override
  Future<FirestoreDoc?> get(String path) async {
    reads++;
    final d = docs[path];
    return d == null ? null : FirestoreDoc(path.split('/').last, d);
  }

  @override
  Future<void> set(String path, Map<String, dynamic> fields, {bool merge = true}) async {
    writes++;
    docs[path] = merge ? {...?docs[path], ...fields} : fields;
  }

  @override
  Future<void> delete(String path) async {
    docs.remove(path);
  }

  @override
  Future<List<FirestoreDoc>> list(String path, {int pageSize = 300}) async {
    reads++;
    return [
      for (final e in docs.entries)
        if (e.key.startsWith('$path/') && !e.key.substring(path.length + 1).contains('/'))
          FirestoreDoc(e.key.split('/').last, e.value),
    ];
  }

  // The rest of Firestore's surface is the HTTP plumbing, which a map does not have.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Track _t(String path, String title, String artist, String album, {int no = 1, int total = 0}) =>
    Track(
      path: path,
      title: title,
      artist: artist,
      album: album,
      trackNo: no,
      trackTotal: total,
      duration: const Duration(seconds: 240),
      isFlac: true,
      sizeBytes: 4096,
      sampleRate: 44100,
      bitsPerSample: 16,
      year: 1994,
    );

void main() {
  late Directory scratch;
  late FakeDb db;
  late LibraryStore pc;
  late LanCatalog catalog;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_mirror_');
    setAppDirForTest(scratch.path);
    db = FakeDb();
    pc = LibraryStore()
      ..rootPath = scratch.path
      ..configDirOverride = scratch.path;
    pc.tracks.addAll([
      _t('${scratch.path}/a1.flac', 'Mysterons', 'Portishead', 'Dummy', no: 1, total: 2),
      _t('${scratch.path}/a2.flac', 'Sour Times', 'Portishead', 'Dummy', no: 2, total: 2),
      // Two pressings of one record, which is the thing a simplified copy would flatten.
      _t('${scratch.path}/b1.flac', 'Larger Than Life', 'Backstreet Boys', 'Millennium',
          no: 1, total: 12),
      _t('${scratch.path}/c1.flac', 'Larger Than Life', 'Backstreet Boys', 'Millennium',
          no: 1, total: 16),
      _t('${scratch.path}/c2.flac', 'I Want It That Way', 'Backstreet Boys', 'Millennium',
          no: 2, total: 16),
    ]);
    pc.rebuildAlbums();
    catalog = LanCatalog(pc);
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  CatalogMirror mirror() => CatalogMirror(db: db, uid: 'u1');

  LibraryStore client() => LibraryStore()
    ..remote = RemoteClient(
        RemoteEndpoint(baseUrl: Uri.parse('http://192.168.0.117:47820'), token: 't'));

  /// What a person sees of an album, in a form two libraries can be compared on.
  List<String> shape(LibraryStore s) => [
        for (final a in s.albums)
          '${a.title} · ${a.artist} · ${a.edition ?? '-'} · '
              '${a.tracks.map((t) => '${t.trackNo} ${t.title}').join('|')}'
      ];

  group('the copy is the catalogue', () {
    test('albums, pressings and track order survive the round trip', () async {
      await mirror().publish(catalog.snapshot());
      final copy = await mirror().fetch();
      expect(copy, isNotNull);

      final mac = client();
      expect(mac.adoptMirror(copy!.json), isTrue);

      expect(shape(mac), shape(pc));
      expect(mac.tracks.length, pc.tracks.length);
      // The pressings are the point: a copy that merged them would look tidier and be wrong.
      expect(mac.albums.where((a) => a.title == 'Millennium').length, 2);
    });

    test('what came from the copy is marked as such, and is not playable', () async {
      await mirror().publish(catalog.snapshot());
      final mac = client();
      mac.adoptMirror((await mirror().fetch())!.json);

      expect(mac.fromCloudMirror, isTrue,
          reason: 'anders doet een tik op play niets en zegt niemand waarom');
      expect(mac.albums, isNotEmpty);
    });
  });

  group('what it costs', () {
    test('an unchanged library is not written again', () async {
      final m = mirror();
      await m.publish(catalog.snapshot());
      final afterFirst = db.writes;

      await m.publish(catalog.snapshot());
      await m.publish(catalog.snapshot());
      expect(db.writes, afterFirst, reason: 'de vingerafdruk is niet veranderd');
    });

    test('a second PC does not rewrite what is already up there', () async {
      await mirror().publish(catalog.snapshot());
      final afterFirst = db.writes;

      // A fresh mirror has no memory of what it wrote, so it must ask before writing.
      await mirror().publish(catalog.snapshot());
      expect(db.writes, afterFirst);
    });

    test('a real change is written', () async {
      final m = mirror();
      await m.publish(catalog.snapshot());
      final afterFirst = db.writes;

      pc.tracks.add(_t('${scratch.path}/d1.flac', 'Roads', 'Portishead', 'Dummy', no: 3, total: 2));
      pc.rebuildAlbums();
      pc.notifyListeners();
      await m.publish(catalog.snapshot());

      expect(db.writes, greaterThan(afterFirst));
      final mac = client();
      mac.adoptMirror((await mirror().fetch())!.json);
      expect(mac.tracks.map((t) => t.title), contains('Roads'));
    });

    test('it is compressed, and one library is one document', () async {
      await mirror().publish(catalog.snapshot());
      final chunks = db.docs.keys.where((k) => k.contains('chunk-')).length;
      expect(chunks, 1, reason: 'meer documenten is meer leesbewerkingen bij elke start');

      final stored = (db.docs['users/u1/catalog/chunk-0']!['data'] as String).length;
      final raw = catalog.snapshot().json.length;
      expect(stored, lessThan(raw),
          reason: 'gzip+base64 hoort kleiner te zijn dan de kale JSON');
    });
  });

  group('half a copy is worse than none', () {
    test('a missing chunk reads as nothing, not as a shrunken library', () async {
      await mirror().publish(catalog.snapshot());
      // What a torn write leaves behind. Returning the albums that did arrive would look exactly
      // like records having been deleted.
      db.docs.remove('users/u1/catalog/chunk-0');
      expect(await mirror().fetch(), isNull);
    });

    test('nothing published yet is simply nothing', () async {
      expect(await mirror().fetch(), isNull);
    });

    test('unreadable contents do not throw at the caller', () async {
      await db.set('users/u1/catalog/meta', {'etag': 'x', 'chunks': 1});
      await db.set('users/u1/catalog/chunk-0', {'data': base64Encode(utf8.encode('geen gzip'))});
      expect(await mirror().fetch(), isNull);
    });
  });

  group('the copy never replaces a live library', () {
    test('a client with a real catalogue keeps it', () async {
      await mirror().publish(catalog.snapshot());
      final copy = await mirror().fetch();

      final mac = client();
      // Stand in for a live load: tracks present, not from the mirror.
      mac.tracks.add(_t('http://192.168.0.117:47820/stream/x.flac', 'Live', 'Iemand', 'Nu'));
      mac.rebuildAlbums();

      // Coming back from a lock screen can land this after the PC has already answered. Replacing
      // a playable library with an unplayable copy of itself is the one outcome nobody wants.
      expect(mac.adoptMirror(copy!.json), isFalse);
      expect(mac.tracks.single.title, 'Live');
      expect(mac.fromCloudMirror, isFalse);
    });

    test('a PC does not adopt a copy at all', () async {
      await mirror().publish(catalog.snapshot());
      final copy = await mirror().fetch();
      // pc owns its files; a cloud copy of them is never the better source.
      expect(pc.adoptMirror(copy!.json), isFalse);
    });
  });
}
