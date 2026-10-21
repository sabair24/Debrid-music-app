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
    this.shuffle = false,
    this.repeat = 'off',
    this.overname = '',
    this.radio,
    this.volume = -1,
  });

  /// Het appvolume van dat toestel (0–100), of -1 als het dat niet meldde (een oudere app).
  final int volume;

  /// Speelt er een radio: rond welke artiest (`artiest`) en hoe hij heet (`naam`). Neemt een ander
  /// toestel over, dan start het dezelfde radio. Null zonder radio.
  final Map<String, dynamic>? radio;

  /// Shuffle en herhalen ('off', 'all', 'one'), zodat ze meegaan als een ander toestel overneemt
  /// (Saber, 17-10-2026).
  final bool shuffle;
  final String repeat;

  /// Van welk toestel dit toestel net overnam ("Hier verder luisteren"): dat toestel pauzeert als
  /// het zichzelf hier ziet staan. Leeg bij een gewone melding. Zie verder_luisteren.dart.
  final String overname;

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
        'shuffle': shuffle,
        'repeat': repeat,
        if (overname.isNotEmpty) 'overname': overname,
        if (radio != null) 'radio': radio,
        if (volume >= 0) 'volume': volume,
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
        shuffle: m['shuffle'] == true,
        repeat: (m['repeat'] ?? 'off') as String,
        overname: (m['overname'] ?? '') as String,
        radio: (m['radio'] as Map?)?.cast<String, dynamic>(),
        volume: (m['volume'] as num?)?.toInt() ?? -1,
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

  /// Duim omhoog of omlaag per nummer: id → `'up'` of `'down'`.
  ///
  /// Een kaart en geen twee verzamelingen, want een nummer heeft precies één oordeel — met twee
  /// verzamelingen kan het in allebei staan en is er geen antwoord op de vraag wat je ervan vindt.
  final Map<String, String> ratings = {};

  /// "Past / past niet in deze radio", per nummer én context — zie `radiosfeer.dart`. Sleutel →
  /// `{v, n, a, t, z, f, at}`. Een weggehaald oordeel blijft als lege `v` staan, zodat een late op van
  /// een toestel dat offline was het niet terugzet (de laatste op `at` wint).
  final Map<String, Map<String, dynamic>> radioSfeer = {};
  PlaybackProgress progress = PlaybackProgress();

  /// Wat elk toestel het laatst meldde, per toestel-id — de zones (Saber, 21-10-2026: "als ik op de pc
  /// een liedje aan het spelen ben, dat de ander devices dit zien"). [progress] is alleen de laatste
  /// melding van wie dan ook; hier staat elk toestel apart, zodat de gsm ziet wat de pc speelt terwijl
  /// de iPad ook iets speelt. Niet op schijf: na een herstart meldt elk spelend toestel binnen vijf
  /// seconden opnieuw. Zie `zones.dart`.
  final Map<String, PlaybackProgress> perToestel = {};

  final _zoneChanges = StreamController<String>.broadcast();

  /// Het toestel-id telkens als [perToestel] voor dat toestel veranderde.
  Stream<String> get zoneChanges => _zoneChanges.stream;

  /// Per toestel hoeveel zijn klok afwijkt van die van de pc (pc min toestel), voor de speelstand.
  final Map<String, int> _klokVerschil = {};

  /// Het laatste "Speel op …" van de pc: welk toestel moet overnemen, met de stand erbij. Niet op
  /// schijf: een verzoek van gisteren voert niemand meer uit. Zie verder_luisteren.dart.
  Map<String, dynamic>? verzoek;

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
      (m['ratings'] as Map?)?.forEach((k, v) {
        if (v == 'up' || v == 'down') ratings[k.toString()] = v as String;
      });
      final oud = DateTime.now().millisecondsSinceEpoch - _tombstoneTtlMs;
      (m['radioSfeer'] as Map?)?.forEach((k, v) {
        if (v is! Map) return;
        final r = v.cast<String, dynamic>();
        // Een weggehaald oordeel van lang geleden mag weg: elk toestel heeft het intussen gezien.
        if ('${r['v'] ?? ''}'.isEmpty && ((r['at'] as num?) ?? 0) < oud) return;
        radioSfeer[k.toString()] = r;
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
        'ratings': ratings,
        'radioSfeer': radioSfeer,
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
        'ratings': ratings,
        'radioSfeer': radioSfeer,
        'progress': progress.toJson(),
        if (verzoek != null) 'verzoek': verzoek,
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

        case 'rating':
          // Duim omhoog of omlaag. Een lege waarde is "ik vind er toch niets van" en HAALT het
          // oordeel weg — dat is geen derde stand maar het ontbreken van een stand, en zo loopt de
          // kaart niet vol met lege waarden.
          final id = (op['trackId'] ?? '') as String;
          if (id.isEmpty) break;
          final waarde = (op['value'] ?? '') as String;
          if (waarde == 'up' || waarde == 'down') {
            durableChanged |= ratings[id] != waarde;
            ratings[id] = waarde;
          } else {
            durableChanged |= ratings.remove(id) != null;
          }

        case 'radio.sfeer':
          // "Past / past niet in deze radio" — zie `radiosfeer.dart`. De laatste op `at` wint.
          final sleutel = (op['key'] ?? '') as String;
          if (sleutel.isEmpty) break;
          final was = radioSfeer[sleutel];
          if (was != null && ((was['at'] as num?) ?? 0) > at) break;
          final v = '${op['v'] ?? ''}';
          radioSfeer[sleutel] = {
            'v': v == 'past' || v == 'pastniet' ? v : '',
            'n': '${op['n'] ?? ''}',
            'a': '${op['a'] ?? ''}',
            't': '${op['t'] ?? ''}',
            'z': '${op['z'] ?? ''}',
            'f': '${op['f'] ?? ''}',
            'at': at,
          };
          durableChanged = true;

        case 'progress':
          // Only ever moves forward. Two devices both reporting means the most recent one is
          // where you actually are; an older report arriving late must not drag you backwards.
          //
          // Op de klok van de PC, sinds 17-10-2026 ("Hier verder luisteren"): een toestel waarvan
          // de klok achterloopt, werd anders stil genegeerd, en dan kon het nooit overnemen. Per
          // toestel wordt onthouden hoeveel zijn klok afwijkt ([_klokVerschil], het kleinste verschil
          // dat ooit gezien is: onderweg komt er alleen vertraging bij). Zo blijft een te late melding
          // van hetzelfde toestel achter, en telt een scheve klok niet meer.
          final verschil = now - at;
          final bekend = _klokVerschil[deviceId];
          final schatting = bekend == null || verschil < bekend ? verschil : bekend;
          _klokVerschil[deviceId] = schatting;
          final opPc = at + schatting;
          final melding = PlaybackProgress(
            trackId: (op['trackId'] ?? '') as String,
            positionMs: (op['positionMs'] as int?) ?? 0,
            queue: [for (final t in (op['queue'] as List? ?? const [])) t.toString()],
            index: (op['index'] as int?) ?? 0,
            playing: (op['playing'] ?? false) as bool,
            updatedAt: opPc,
            deviceId: deviceId,
            deviceName: deviceName,
            shuffle: op['shuffle'] == true,
            repeat: (op['repeat'] ?? 'off') as String,
            overname: (op['overname'] ?? '') as String,
            radio: (op['radio'] as Map?)?.cast<String, dynamic>(),
            volume: (op['volume'] as num?)?.toInt() ?? -1,
          );
          // Per toestel eerst: ook een melding die achter de laatste van een ANDER toestel valt, is
          // voor zijn eigen zone nieuw. Alleen een oudere van hetzelfde toestel valt weg.
          final eerder = perToestel[deviceId];
          if (eerder == null || opPc >= eerder.updatedAt) {
            perToestel[deviceId] = melding;
            if (deviceId.isNotEmpty) _zoneChanges.add(deviceId);
          }
          if (opPc < progress.updatedAt) break;
          progress = melding;
          progressChanged = true;

        case 'verzoek':
          // "Speel op …": het toestel [naar] neemt over, met de stand die erbij staat.
          final naar = (op['naar'] ?? '') as String;
          if (naar.isEmpty) break;
          verzoek = {...op, 'at': now, 'deviceId': deviceId, 'deviceName': deviceName}..remove('type');
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
        if (progressChanged && verzoek != null) 'verzoek': verzoek,
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
    await _zoneChanges.close();
  }
}
