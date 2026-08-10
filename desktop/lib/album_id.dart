/// A name for an album that does not change when you rename the album.
///
/// Everything the app remembers ABOUT a record is currently filed under `artist|title`: whether its
/// pressings were merged, which scan is the back and which is the disc, its styles, its cached
/// cover, its cached info. Correct the artist — the single most common edit there is — and every one
/// of those keys moves, so all of it is orphaned at once. The hand-assigned scans go back to being
/// guesses, the merged record un-merges, the cover cache misses and refetches. The user did not
/// throw any of that away; the key did.
///
/// So: an opaque uid per album, held against its TRACK PATHS. Paths do not move when a name
/// changes, which is exactly the property the text keys lack.
///
/// **This is an observation, never an input.** The uid must not reach `_groupKey`, `editionSplit`
/// or `_byBase`. Grouping decides what an album IS; if identity then fed back into grouping, the
/// merge/split/renumber machinery would gain a loop where last night's answer constrains tonight's.
/// It watches what grouping decided and puts a durable name on it. Nothing more.
///
/// The wire ids in `lan/ids.dart` are deliberately NOT this. Those are on the rows of the Shield and
/// the phone, and album favourites hang off them; re-issuing them to tidy an internal key would
/// detach every favourite in the house.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'paths.dart';
import 'models.dart';

/// Path → uid, with enough bookkeeping to survive splits, merges and moves.
class AlbumUids {
  AlbumUids({required this.dir});

  /// Where `album_uids.json` lives. A callback rather than a string because LibraryStore's config
  /// folder can be redirected after construction (a test hands it a scratch dir), and reading it
  /// once at construction would quietly write the index into the real one.
  final String Function() dir;

  final Map<String, String> _byPath = {};

  /// When each uid was first handed out. Only used to break a tie deterministically: two groups
  /// with equal claims must not swap identities depending on map iteration order.
  final Map<String, int> _minted = {};

  final _rng = Random.secure();
  Timer? _save;
  bool _dirty = false;

  File get _file => File('${dir()}${Platform.pathSeparator}album_uids.json');

  /// The uid for an album, or empty before [reconcile] has seen it.
  String uidOf(Album a) {
    for (final t in a.tracks) {
      final u = _byPath[t.path];
      if (u != null) return u;
    }
    return '';
  }

  /// The uid recorded against one file.
  @visibleForTesting
  String? uidOfPath(String path) => _byPath[path];

  int get count => _byPath.length;

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final j = jsonDecode(await _file.readAsString());
      if (j is! Map) return;
      _byPath.clear();
      _minted.clear();
      for (final e in (j['paths'] as Map?)?.entries ?? const <MapEntry>[]) {
        _byPath['${e.key}'] = '${e.value}';
      }
      for (final e in (j['minted'] as Map?)?.entries ?? const <MapEntry>[]) {
        final ms = e.value;
        if (ms is num) _minted['${e.key}'] = ms.toInt();
      }
    } catch (_) {/* an unreadable index costs a re-mint, not a crash */}
  }

  /// Give every album a uid, keeping the one its tracks already carry.
  ///
  /// Called at the tail of every regroup. The rules fall out of one idea — the uid belongs to the
  /// FILES, and an album is whichever group holds most of them:
  ///
  /// * rename         → the paths did not move, so the tally is unchanged and so is the uid
  /// * edition split  → the side holding most of the tracks keeps it, the other side mints
  /// * merge          → the bigger of the two wins, the smaller's uid is simply no longer claimed
  /// * a track leaves → the survivors still out-vote it
  ///
  /// Returns true when anything was minted or moved, so the caller can avoid pointless writes: this
  /// runs on every rebuild and a library that has not changed must cost no disk at all.
  bool reconcile(Iterable<Album> albums) {
    var changed = false;
    final claimed = <String>{};

    for (final a in albums) {
      if (a.tracks.isEmpty) continue;

      final votes = <String, int>{};
      for (final t in a.tracks) {
        final u = _byPath[t.path];
        // A uid already taken by an earlier group this pass cannot also be this group's: a merge
        // leaves the loser's tracks pointing at a uid the winner now holds.
        if (u == null || claimed.contains(u)) continue;
        votes[u] = (votes[u] ?? 0) + 1;
      }

      String uid;
      if (votes.isEmpty) {
        uid = _mint();
        changed = true;
      } else {
        uid = votes.entries.reduce((x, y) {
          if (x.value != y.value) return x.value > y.value ? x : y;
          // Same number of votes: the older name wins. Arbitrary, but STABLE — without it the
          // winner depends on iteration order and an album's identity flickers between restarts.
          return (_minted[x.key] ?? 0) <= (_minted[y.key] ?? 0) ? x : y;
        }).key;
      }
      claimed.add(uid);

      for (final t in a.tracks) {
        if (_byPath[t.path] == uid) continue;
        _byPath[t.path] = uid;
        changed = true;
      }
    }

    if (changed) _scheduleSave();
    return changed;
  }

  /// Carry a file's uid to where the file now is.
  ///
  /// The same hole [LibraryStore._reKeyCorrection] exists for, and it has to be closed at the same
  /// three places: a move the app performed itself leaves the entry under the old name, so without
  /// this, tidying a folder renames the album from the store's point of view.
  void reKey(String from, String to) {
    if (from == to) return;
    final u = _byPath.remove(from);
    if (u == null) return;
    _byPath[to] = u;
    _dirty = true;
    _scheduleSave();
  }

  /// Forget paths that are no longer in the library.
  ///
  /// Deliberately NOT keyed on whether the file exists — the same trap that emptied
  /// `corrections.json` when a drive was not mounted. The caller passes the paths of a scan that
  /// actually found music, and an empty set is ignored.
  void prune(Set<String> livePaths) {
    if (livePaths.isEmpty) return;
    // Vouwen, met dezelfde vouw als de aanroeper. Dit ontbrak, en daardoor overleefde op Windows
    // geen enkel pad: `livePaths` kwam er kleingemaakt in, `_byPath` houdt de schrijfwijze van de
    // schijf, en op een wortel als `D:\Flac music 2024` matcht dat nooit. Elke scan gooide het hele
    // register leeg — zie [padSleutel] voor de meting.
    final dead = [for (final p in _byPath.keys) if (!livePaths.contains(padSleutel(p))) p];
    if (dead.isEmpty) return;
    for (final p in dead) {
      _byPath.remove(p);
    }
    _scheduleSave();
  }

  String _mint() {
    final b = List<int>.generate(12, (_) => _rng.nextInt(256));
    final uid = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
    _minted[uid] = DateTime.now().millisecondsSinceEpoch;
    return uid;
  }

  /// Debounced, because a regroup can happen several times in a second while a correction settles.
  void _scheduleSave() {
    _dirty = true;
    _save?.cancel();
    _save = Timer(const Duration(seconds: 2), () => unawaited(flush()));
  }

  /// Write now. Via a temp file and a rename, so a crash mid-write cannot leave a half-parsed index
  /// — which would rename every album at the next start.
  Future<void> flush() async {
    if (!_dirty) return;
    _dirty = false;
    _save?.cancel();
    _save = null;
    try {
      await Directory(dir()).create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode({'paths': _byPath, 'minted': _minted}));
      await tmp.rename(_file.path);
    } catch (e) {
      debugPrint('album_uids.json not written: $e');
    }
  }

  void dispose() {
    _save?.cancel();
    _save = null;
  }
}
