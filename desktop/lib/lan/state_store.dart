import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A playlist, as every device sees it.
///
/// [deletedAt] is a tombstone rather than a removal: a device that was off when you deleted a
/// playlist has to be told it is gone, and an entry that simply vanished from the list would be
/// read as "I haven't got that one yet" and pushed straight back.
class Playlist {
  Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  String name;
  List<String> trackIds;
  int updatedAt;
  int? deletedAt;

  bool get deleted => deletedAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'updatedAt': updatedAt,
        'deletedAt': deletedAt,
      };

  static Playlist fromJson(Map<String, dynamic> m) => Playlist(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        trackIds: [for (final t in (m['trackIds'] as List? ?? const [])) t.toString()],
        updatedAt: (m['updatedAt'] as int?) ?? 0,
        deletedAt: m['deletedAt'] as int?,
      );
}

/// Where you are in a track, and what is queued behind it — the "carry on where you left off"
/// that follows you from the Mac to the iPad.
class PlaybackProgress {
  PlaybackProgress({
    this.trackId = '',
    this.positionMs = 0,
    this.queue = const [],
    this.index = 0,
    this.playing = false,
    this.updatedAt = 0,
    this.deviceId = '',
    this.deviceName = '',
  });

  final String trackId;
  final int positionMs;
  final List<String> queue;
  final int index;
  final bool playing;
  final int updatedAt;
  final String deviceId;
  final String deviceName;

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'positionMs': positionMs,
        'queue': queue,
        'index': index,
        'playing': playing,
        'updatedAt': updatedAt,
        'deviceId': deviceId,
        'deviceName': deviceName,
      };

  static PlaybackProgress fromJson(Map<String, dynamic> m) => PlaybackProgress(
        trackId: (m['trackId'] ?? '') as String,
        positionMs: (m['positionMs'] as int?) ?? 0,
        queue: [for (final t in (m['queue'] as List? ?? const [])) t.toString()],
        index: (m['index'] as int?) ?? 0,
        playing: (m['playing'] ?? false) as bool,
        updatedAt: (m['updatedAt'] as int?) ?? 0,
        deviceId: (m['deviceId'] ?? '') as String,
        deviceName: (m['deviceName'] ?? '') as String,
      );
}

/// How often a track was played, and when last — the shared "recently played".
class PlayStat {
  PlayStat({this.count = 0, this.lastPlayedMs = 0});
  int count;
  int lastPlayedMs;

  Map<String, dynamic> toJson() => {'count': count, 'lastPlayedMs': lastPlayedMs};

  static PlayStat fromJson(Map<String, dynamic> m) => PlayStat(
        count: (m['count'] as int?) ?? 0,
        lastPlayedMs: (m['lastPlayedMs'] as int?) ?? 0,
      );
}

/// The part of the library that is not the files: playlists, favourites, where you are in a
/// track, and what you've been playing. The PC holds it; every device reads and writes it here.
///
/// Two revisions, not one. Playlists and favourites change rarely and are worth telling everyone
/// about; the play position changes several times a second. Sharing one revision would have every
/// device re-fetching the whole state continuously while a track plays, so the position carries
/// its own counter and rides along inside the event instead of triggering a fetch.
class LanStateStore {
  LanStateStore(this.file);

  final File file;

  final Set<String> favoriteTracks = {};
  final Set<String> favoriteAlbums = {};
  final Map<String, Playlist> playlists = {};
  final Map<String, PlayStat> plays = {};
  PlaybackProgress progress = PlaybackProgress();

  int rev = 0;
  int progressRev = 0;

  final _changes = StreamController<Map<String, dynamic>>.broadcast();

  /// Bumps of [rev] / [progressRev], for the SSE feed.
  Stream<Map<String, dynamic>> get changes => _changes.stream;

  Timer? _saveTimer;

  /// Tombstones older than this are dropped: every device has long since caught up, and keeping
  /// them forever would grow the file without bound.
  static const _tombstoneTtlMs = 30 * 24 * 60 * 60 * 1000;

  Future<void> load() async {
    try {
      if (!await file.exists()) return;
      final m = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      rev = (m['rev'] as int?) ?? 0;
      progressRev = (m['progressRev'] as int?) ?? 0;
      favoriteTracks.addAll([for (final t in (m['favoriteTracks'] as List? ?? const [])) t.toString()]);
      favoriteAlbums.addAll([for (final t in (m['favoriteAlbums'] as List? ?? const [])) t.toString()]);
      for (final p in (m['playlists'] as List? ?? const [])) {
        final pl = Playlist.fromJson((p as Map).cast<String, dynamic>());
        playlists[pl.id] = pl;
      }
      (m['plays'] as Map?)?.forEach((k, v) {
        plays[k.toString()] = PlayStat.fromJson((v as Map).cast<String, dynamic>());
      });
      if (m['progress'] != null) {
        progress = PlaybackProgress.fromJson((m['progress'] as Map).cast<String, dynamic>());
      }
    } catch (_) {
      // A truncated or hand-edited file must not stop the app from starting. Losing playlists is
      // bad; refusing to boot is worse, and the next save writes a clean file.
    }
  }

  Map<String, dynamic> toJson() => {
        'rev': rev,
        'progressRev': progressRev,
        'favoriteTracks': favoriteTracks.toList(),
        'favoriteAlbums': favoriteAlbums.toList(),
        'playlists': [for (final p in playlists.values) p.toJson()],
        'plays': {for (final e in plays.entries) e.key: e.value.toJson()},
        'progress': progress.toJson(),
      };

  /// The whole state a client needs. Small by design — playlists and favourites are ids, and
  /// plays only exist for tracks actually played.
  Map<String, dynamic> snapshot() => {
        'rev': rev,
        'progressRev': progressRev,
        'favoriteTracks': favoriteTracks.toList(),
        'favoriteAlbums': favoriteAlbums.toList(),
        'playlists': [for (final p in playlists.values) p.toJson()],
        'plays': {for (final e in plays.entries) e.key: e.value.toJson()},
        'progress': progress.toJson(),
      };

  /// Apply a batch of operations from one device. Returns the resulting revisions.
  ///
  /// Unknown op types are skipped rather than refused: an older PC must keep working with a newer
  /// client, and dropping the one op it doesn't know beats rejecting the whole batch.
  Map<String, int> applyOps(List<dynamic> ops, {String deviceId = '', String deviceName = ''}) {
    var durableChanged = false;
    var progressChanged = false;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final raw in ops) {
      if (raw is! Map) continue;
      final op = raw.cast<String, dynamic>();
      final at = (op['at'] as int?) ?? now;
      switch (op['type']) {
        case 'favorite':
          final id = (op['id'] ?? '') as String;
          if (id.isEmpty) break;
          final set = op['kind'] == 'album' ? favoriteAlbums : favoriteTracks;
          final on = (op['on'] ?? true) as bool;
          durableChanged |= on ? set.add(id) : set.remove(id);

        case 'playlist.create':
          final id = (op['id'] ?? '') as String;
          if (id.isEmpty || playlists.containsKey(id)) break;
          playlists[id] = Playlist(
            id: id,
            name: (op['name'] ?? 'Nieuwe afspeellijst') as String,
            trackIds: [for (final t in (op['trackIds'] as List? ?? const [])) t.toString()],
            updatedAt: at,
          );
          durableChanged = true;

        case 'playlist.rename':
          final p = playlists[op['id']];
          // Last write wins, by the client's clock. An edit older than what we already have is a
          // device that was offline replaying its backlog — its version is genuinely out of date.
          if (p == null || at < p.updatedAt) break;
          p.name = (op['name'] ?? p.name) as String;
          p.updatedAt = at;
          durableChanged = true;

        case 'playlist.setTracks':
          final p = playlists[op['id']];
          if (p == null || at < p.updatedAt) break;
          p.trackIds = [for (final t in (op['trackIds'] as List? ?? const [])) t.toString()];
          p.updatedAt = at;
          durableChanged = true;

        case 'playlist.add':
          final p = playlists[op['id']];
          if (p == null) break;
          final add = [for (final t in (op['trackIds'] as List? ?? const [])) t.toString()];
          // Adding the same song twice is a real thing to want in a playlist, so no dedupe here.
          p.trackIds = [...p.trackIds, ...add];
          p.updatedAt = at;
          durableChanged = true;

        case 'playlist.remove':
          final p = playlists[op['id']];
          if (p == null) break;
          final drop = {for (final t in (op['trackIds'] as List? ?? const [])) t.toString()};
          p.trackIds = [for (final t in p.trackIds) if (!drop.contains(t)) t];
          p.updatedAt = at;
          durableChanged = true;

        case 'playlist.delete':
          final p = playlists[op['id']];
          if (p == null || p.deleted) break;
          p.deletedAt = at;
          p.trackIds = const [];
          p.updatedAt = at;
          durableChanged = true;

        case 'played':
          final id = (op['trackId'] ?? '') as String;
          if (id.isEmpty) break;
          final stat = plays.putIfAbsent(id, PlayStat.new);
          stat.count += 1;
          if (at > stat.lastPlayedMs) stat.lastPlayedMs = at;
          durableChanged = true;

        case 'progress':
          // Only ever moves forward. Two devices both reporting means the most recent one is
          // where you actually are; an older report arriving late must not drag you backwards.
          if (at < progress.updatedAt) break;
          progress = PlaybackProgress(
            trackId: (op['trackId'] ?? '') as String,
            positionMs: (op['positionMs'] as int?) ?? 0,
            queue: [for (final t in (op['queue'] as List? ?? const [])) t.toString()],
            index: (op['index'] as int?) ?? 0,
            playing: (op['playing'] ?? false) as bool,
            updatedAt: at,
            deviceId: deviceId,
            deviceName: deviceName,
          );
          progressChanged = true;
      }
    }

    if (durableChanged) rev++;
    if (progressChanged) progressRev++;
    if (durableChanged || progressChanged) {
      _pruneTombstones();
      _scheduleSave();
      _changes.add({
        'rev': rev,
        'progressRev': progressRev,
        if (progressChanged) 'progress': progress.toJson(),
        'from': deviceId,
      });
    }
    return {'rev': rev, 'progressRev': progressRev};
  }

  void _pruneTombstones() {
    final cutoff = DateTime.now().millisecondsSinceEpoch - _tombstoneTtlMs;
    playlists.removeWhere((_, p) => p.deleted && p.deletedAt! < cutoff);
  }

  /// Writes are debounced: the play position alone would otherwise hit the disk several times a
  /// second, for a file nothing reads until the next start.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), save);
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      await file.parent.create(recursive: true);
      // Write beside it and rename: a power cut halfway through a direct write leaves a truncated
      // file, and that file is the only copy of your playlists.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(toJson()));
      await tmp.rename(file.path);
    } catch (_) {}
  }

  Future<void> dispose() async {
    await save();
    await _changes.close();
  }
}
