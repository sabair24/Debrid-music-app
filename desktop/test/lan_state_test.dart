import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/lan/state_store.dart';
import 'package:flutter_test/flutter_test.dart';

LanStateStore _store(Directory dir) =>
    LanStateStore(File('${dir.path}/state.json'));

Map<String, dynamic> _op(String type, Map<String, dynamic> rest) => {'type': type, ...rest};

void main() {
  late Directory dir;
  late LanStateStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('debridmusic_state_');
    store = _store(dir);
  });

  tearDown(() async {
    await store.dispose();
    dir.deleteSync(recursive: true);
  });

  test('a favourite survives a round trip to disk', () async {
    store.applyOps([_op('favorite', {'kind': 'track', 'id': 'abc', 'on': true})]);
    await store.save();

    final reopened = _store(dir);
    await reopened.load();
    expect(reopened.favoriteTracks, contains('abc'));
    expect(reopened.rev, store.rev);
    await reopened.dispose();
  });

  test('unfavouriting removes it again', () {
    store.applyOps([_op('favorite', {'kind': 'album', 'id': 'x', 'on': true})]);
    expect(store.favoriteAlbums, contains('x'));
    store.applyOps([_op('favorite', {'kind': 'album', 'id': 'x', 'on': false})]);
    expect(store.favoriteAlbums, isEmpty);
  });

  test('a no-op does not bump the revision', () {
    store.applyOps([_op('favorite', {'kind': 'track', 'id': 'a', 'on': true})]);
    final rev = store.rev;
    // Already a favourite — nothing changed, so no device should be told to re-sync.
    store.applyOps([_op('favorite', {'kind': 'track', 'id': 'a', 'on': true})]);
    expect(store.rev, rev);
  });

  test('playlists are created, filled and renamed', () {
    store.applyOps([
      _op('playlist.create', {'id': 'p1', 'name': 'Zondagochtend', 'at': 100}),
      _op('playlist.add', {'id': 'p1', 'trackIds': ['t1', 't2'], 'at': 110}),
      _op('playlist.rename', {'id': 'p1', 'name': 'Zondag', 'at': 120}),
    ]);
    final p = store.playlists['p1']!;
    expect(p.name, 'Zondag');
    expect(p.trackIds, ['t1', 't2']);
  });

  test('the same song twice in a playlist is allowed', () {
    store.applyOps([
      _op('playlist.create', {'id': 'p', 'name': 'x', 'at': 1}),
      _op('playlist.add', {'id': 'p', 'trackIds': ['t1'], 'at': 2}),
      _op('playlist.add', {'id': 'p', 'trackIds': ['t1'], 'at': 3}),
    ]);
    expect(store.playlists['p']!.trackIds, ['t1', 't1']);
  });

  test('a stale edit from a device that was offline loses to a newer one', () {
    store.applyOps([
      _op('playlist.create', {'id': 'p', 'name': 'Origineel', 'at': 100}),
      _op('playlist.rename', {'id': 'p', 'name': 'Nieuw', 'at': 200}),
    ]);
    // The iPad wakes up and replays an edit it made before the Mac's.
    store.applyOps([_op('playlist.rename', {'id': 'p', 'name': 'Oud', 'at': 150})]);
    expect(store.playlists['p']!.name, 'Nieuw');
  });

  test('a deleted playlist leaves a tombstone, so other devices hear about it', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    store.applyOps([
      _op('playlist.create', {'id': 'p', 'name': 'Weg', 'at': now}),
      _op('playlist.delete', {'id': 'p', 'at': now}),
    ]);
    // Still present, but marked — a plain removal would read as "I don't have that one yet"
    // on the next device to sync, and it would push the playlist straight back.
    expect(store.playlists.containsKey('p'), isTrue);
    expect(store.playlists['p']!.deleted, isTrue);
    expect(store.snapshot()['playlists'], hasLength(1));
  });

  test('an ancient tombstone is eventually swept up', () {
    final old = DateTime.now().millisecondsSinceEpoch - const Duration(days: 40).inMilliseconds;
    store.applyOps([
      _op('playlist.create', {'id': 'p', 'name': 'oud', 'at': old}),
      _op('playlist.delete', {'id': 'p', 'at': old}),
    ]);
    // Any later change triggers the sweep.
    store.applyOps([_op('favorite', {'kind': 'track', 'id': 'z', 'on': true})]);
    expect(store.playlists.containsKey('p'), isFalse);
  });

  test('play position moves forward only', () {
    store.applyOps([_op('progress', {'trackId': 't1', 'positionMs': 60000, 'at': 500})],
        deviceId: 'mac', deviceName: 'Mac');
    expect(store.progress.positionMs, 60000);
    expect(store.progress.deviceName, 'Mac');

    // A late report from the iPad about where it was a minute ago must not drag you back.
    store.applyOps([_op('progress', {'trackId': 't1', 'positionMs': 10000, 'at': 400})],
        deviceId: 'ipad');
    expect(store.progress.positionMs, 60000);

    store.applyOps([_op('progress', {'trackId': 't1', 'positionMs': 90000, 'at': 600})],
        deviceId: 'ipad', deviceName: 'iPad');
    expect(store.progress.positionMs, 90000);
    expect(store.progress.deviceName, 'iPad');
  });

  test('the position has its own counter, so a playing track does not spam re-syncs', () {
    store.applyOps([_op('favorite', {'kind': 'track', 'id': 'a', 'on': true})]);
    final rev = store.rev;

    for (var i = 1; i <= 5; i++) {
      store.applyOps([_op('progress', {'trackId': 't', 'positionMs': i * 1000, 'at': i})]);
    }
    // Five position updates, and not one device was told its library is out of date.
    expect(store.rev, rev);
    expect(store.progressRev, 5);
  });

  test('play counts accumulate and remember when', () {
    store.applyOps([
      _op('played', {'trackId': 't1', 'at': 1000}),
      _op('played', {'trackId': 't1', 'at': 2000}),
      _op('played', {'trackId': 't2', 'at': 1500}),
    ]);
    expect(store.plays['t1']!.count, 2);
    expect(store.plays['t1']!.lastPlayedMs, 2000);
    expect(store.plays['t2']!.count, 1);
  });

  test('an op type we do not know is skipped, not fatal', () {
    store.applyOps([
      _op('from.a.newer.client', {'whatever': true}),
      _op('favorite', {'kind': 'track', 'id': 'ok', 'on': true}),
    ]);
    expect(store.favoriteTracks, contains('ok'));
  });

  test('junk in the batch does not take the good ops down with it', () {
    store.applyOps([
      'not a map',
      42,
      _op('favorite', {'kind': 'track', 'id': 'ok', 'on': true}),
    ]);
    expect(store.favoriteTracks, contains('ok'));
  });

  test('a truncated state file does not stop the app from starting', () async {
    File('${dir.path}/state.json').writeAsStringSync('{"rev": 3, "playlists": [{"id"');
    final reopened = _store(dir);
    await reopened.load();
    expect(reopened.playlists, isEmpty);
    // And it can still be written to afterwards.
    reopened.applyOps([_op('favorite', {'kind': 'track', 'id': 'a', 'on': true})]);
    await reopened.save();
    expect(jsonDecode(File('${dir.path}/state.json').readAsStringSync()), isA<Map>());
    await reopened.dispose();
  });

  test('changes are announced, so the event feed can push them', () async {
    final seen = <Map<String, dynamic>>[];
    final sub = store.changes.listen(seen.add);
    store.applyOps([_op('favorite', {'kind': 'track', 'id': 'a', 'on': true})], deviceId: 'ipad');
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(1));
    expect(seen.first['rev'], store.rev);
    expect(seen.first['from'], 'ipad');
    await sub.cancel();
  });
}
