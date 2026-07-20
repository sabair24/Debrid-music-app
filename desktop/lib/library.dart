import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'enrichment.dart';
import 'flac_tags.dart';
import 'models.dart';
import 'organize.dart';
import 'settings.dart';

const _audioExt = {'.flac', '.mp3', '.m4a', '.wav', '.ogg', '.opus', '.aac', '.wma', '.alac'};

String _ext(String p) {
  final i = p.lastIndexOf('.');
  return i < 0 ? '' : p.substring(i).toLowerCase();
}

String _baseName(String p) {
  final s = p.replaceAll('\\', '/').split('/').last;
  final i = s.lastIndexOf('.');
  return i < 0 ? s : s.substring(0, i);
}

/// Pass 1 (runs in a background isolate): read tags only — fast + low memory.
List<Map<String, dynamic>> _scanTags(String root) {
  final out = <Map<String, dynamic>>[];
  final dir = Directory(root);
  if (!dir.existsSync()) return out;
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is! File || !_audioExt.contains(_ext(e.path))) continue;
    var addedMs = 0, sizeBytes = 0;
    try {
      final st = e.statSync();
      addedMs = st.modified.millisecondsSinceEpoch;
      sizeBytes = st.size;
    } catch (_) {}
    // FLAC goes through our own parser first: the package throws on tags it can't parse (a vinyl
    // "A3" track number is enough) and LEAKS THE FILE HANDLE when it does, which would leave that
    // track unmovable and undeletable for the rest of the session. See readTags().
    if (_ext(e.path) == '.flac') {
      final v = readFlacTags(e);
      if (v != null && (v.title != null || v.artist != null || v.album != null)) {
        out.add({
          'path': e.path,
          'title': v.title ?? _baseName(e.path),
          'artist': v.artist ?? 'Onbekende artiest',
          'album': v.album ?? '',
          'trackNo': v.trackNo,
          'durationMs': v.duration?.inMilliseconds ?? 0,
          'isFlac': true,
          'year': v.year,
          'genre': v.genre,
          'addedMs': addedMs,
          'sizeBytes': sizeBytes,
        });
        continue;
      }
    }
    try {
      final m = readMetadata(e, getImage: false);
      out.add({
        'path': e.path,
        'title': (m.title?.trim().isNotEmpty ?? false) ? m.title!.trim() : _baseName(e.path),
        'artist': (m.artist?.trim().isNotEmpty ?? false) ? m.artist!.trim() : 'Onbekende artiest',
        'album': m.album?.trim() ?? '', // empty => single
        'trackNo': m.trackNumber ?? 0,
        'durationMs': m.duration?.inMilliseconds ?? 0,
        'isFlac': _ext(e.path) == '.flac',
        'year': (m.year != null && m.year!.year > 1000) ? m.year!.year : null,
        'genre': (m.genres.isNotEmpty) ? m.genres.first : null,
        'addedMs': addedMs,
        'sizeBytes': sizeBytes,
      });
    } catch (_) {}
  }
  return out;
}

/// Pass 2 (background isolate): read one embedded cover per album.
Map<String, Uint8List> _readCovers(List<String> paths) {
  final out = <String, Uint8List>{};
  for (final p in paths) {
    try {
      final m = readMetadata(File(p), getImage: true);
      if (m.pictures.isNotEmpty) out[p] = m.pictures.first.bytes;
    } catch (_) {}
  }
  return out;
}

/// Scans the music folder, groups into albums/singles, reads covers, and enriches.
class LibraryStore extends ChangeNotifier {
  final List<Track> tracks = [];
  List<Album> albums = [];
  bool scanning = false;
  int scanned = 0;
  bool enriching = false;
  bool _rescanQueued = false;
  final Map<String, Uint8List> artistImages = {};
  final Map<String, String> artistBios = {};
  String rootPath = r'D:\Flac music 2024';

  // Fast lookups for the flat Tracks view (covers) and playback resume (path → track).
  final Map<String, Album> _albumByPath = {};

  /// normalised "artist|title" → the copy we already have. Lets a download be skipped instead of
  /// creating a duplicate. Version markers stay in the key, so "(Live)" / "(Radio Edit)" / a
  /// compilation cut are all still treated as DIFFERENT tracks and download normally.
  final Map<String, Track> _owned = {};

  /// The track we already own that matches this artist+title (null if we don't have it).
  Track? ownedTrack(String artist, String title) => _owned[trackIdentity(artist, title)];

  /// Keep one copy per track within an album — the best format, then the longest/biggest — so a
  /// second download of the same song doesn't show up twice in the tracklist.
  List<Track> _dedupeTracks(List<Track> ts) {
    final best = <String, Track>{};
    for (final t in ts) {
      final id = trackIdentity(t.artist, t.title);
      final cur = best[id];
      if (cur == null) {
        best[id] = t;
        continue;
      }
      final better = formatRank(t.path) > formatRank(cur.path) ||
          (formatRank(t.path) == formatRank(cur.path) &&
              (t.duration?.inMilliseconds ?? 0) > (cur.duration?.inMilliseconds ?? 0));
      if (better) best[id] = t;
    }
    return best.values.toList();
  }
  final Map<String, Track> _trackByPath = {};

  /// The album cover for a track (covers live on the Album, not the Track).
  Uint8List? coverForTrack(Track t) => _albumByPath[t.path]?.cover;

  /// Resolve a saved file path back to a library track (for resume).
  Track? trackByPath(String path) => _trackByPath[path];

  // Manual metadata corrections (non-destructive): file path -> {title,artist,album}.
  // Applied to scanned tracks so wrong tags are fixed without touching the files.
  final Map<String, Map<String, String>> _corrections = {};

  String get _appDir {
    final base = Platform.environment['APPDATA'] ?? Directory.current.path;
    return '$base${Platform.pathSeparator}DebridMusic';
  }

  File get _correctionsFile => File('$_appDir${Platform.pathSeparator}corrections.json');

  // ── Hidden tracks ─────────────────────────────────────────────────────────
  // "Remove from library only" keeps the FILE on disk but excludes it from the library. The
  // paths live in hidden.json so a rescan doesn't bring them straight back.
  final Set<String> _hidden = {};
  File get _hiddenFile => File('$_appDir${Platform.pathSeparator}hidden.json');

  Future<void> loadHidden() async {
    try {
      final f = _hiddenFile;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as List<dynamic>;
      _hidden
        ..clear()
        ..addAll(j.map((e) => e.toString()));
    } catch (_) {}
  }

  Future<void> _saveHidden() async {
    try {
      await Directory(_appDir).create(recursive: true);
      await _hiddenFile.writeAsString(jsonEncode(_hidden.toList()));
    } catch (_) {}
  }

  /// Number of files currently hidden but still on disk (shown in Settings so it's not a
  /// one-way door — the user can always bring them back).
  int get hiddenCount => _hidden.length;

  /// Un-hide everything: the files are still on disk, so a rescan restores them.
  Future<void> restoreHidden() async {
    _hidden.clear();
    await _saveHidden();
    await scan();
  }

  /// Remove tracks from the library. With [fromDisk] the files are DELETED permanently;
  /// otherwise they're only excluded from the library and stay on disk.
  /// Returns how many files were actually deleted from disk.
  Future<int> removeTracks(Iterable<String> paths, {required bool fromDisk}) async {
    final list = paths.toList();
    var deleted = 0;
    if (fromDisk) {
      for (final p in list) {
        try {
          final f = File(p);
          if (await f.exists()) {
            await f.delete();
            deleted++;
          }
        } catch (_) {/* locked/permission — leave it, it stays visible */}
      }
      // Files are gone, so they can't come back on a rescan; no need to remember them.
      _hidden.removeAll(list);
    } else {
      _hidden.addAll(list);
    }
    await _saveHidden();
    tracks.removeWhere((t) => list.contains(t.path));
    _buildAlbums();
    notifyListeners();
    return deleted;
  }

  Future<void> loadCorrections() async {
    try {
      final f = _correctionsFile;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _corrections.clear();
      j.forEach((path, v) {
        if (v is Map) {
          _corrections[path] = v.map((k, val) => MapEntry(k.toString(), val.toString()));
        }
      });
    } catch (_) {}
  }

  Future<void> _saveCorrections() async {
    try {
      await Directory(_appDir).create(recursive: true);
      await _correctionsFile.writeAsString(jsonEncode(_corrections));
    } catch (_) {}
  }

  Track _applyCorrection(Track t) {
    final c = _corrections[t.path];
    if (c == null) return t;
    return Track(
      path: t.path,
      title: c['title'] ?? t.title,
      artist: c['artist'] ?? t.artist,
      album: c.containsKey('album') ? c['album']! : t.album,
      trackNo: t.trackNo,
      duration: t.duration,
      isFlac: t.isFlac,
      year: t.year,
      genre: t.genre,
      addedMs: t.addedMs,
      sizeBytes: t.sizeBytes,
    );
  }

  /// Apply a manual correction to [target] (artist/album for an album, title for a
  /// single) and optionally a user-picked cover. Persisted + reflected immediately.
  Future<void> applyCorrection(
    Album target,
    AppSettings settings, {
    String? artist,
    String? albumTitle,
    String? title,
    Uint8List? coverBytes,
  }) async {
    for (final t in target.tracks) {
      final c = _corrections.putIfAbsent(t.path, () => {});
      if (artist != null && artist.trim().isNotEmpty) c['artist'] = artist.trim();
      if (albumTitle != null && albumTitle.trim().isNotEmpty && !target.isSingle) {
        c['album'] = albumTitle.trim();
      }
      if (title != null && title.trim().isNotEmpty && target.isSingle) c['title'] = title.trim();
    }
    await _saveCorrections();

    // Re-apply corrections to the in-memory tracks + regroup. _buildAlbums() preserves each
    // album's covers across the rebuild, so the grid no longer blanks here.
    final corrected = tracks.map(_applyCorrection).toList();
    tracks
      ..clear()
      ..addAll(corrected);
    _buildAlbums();

    // Find the regrouped album this correction produced, and attach the new cover.
    final newArtist = (artist?.trim().isNotEmpty ?? false) ? artist!.trim() : target.artist;
    final newTitle = target.isSingle
        ? ((title?.trim().isNotEmpty ?? false) ? title!.trim() : target.title)
        : ((albumTitle?.trim().isNotEmpty ?? false) ? albumTitle!.trim() : target.title);
    final paths = target.tracks.map((t) => t.path).toSet();
    Album? match;
    for (final a in albums) {
      final sameId = a.artist.toLowerCase() == newArtist.toLowerCase() &&
          a.title.toLowerCase() == newTitle.toLowerCase();
      if (sameId || a.tracks.any((t) => paths.contains(t.path))) {
        match = a;
        if (sameId) break;
      }
    }
    if (match != null && coverBytes != null && coverBytes.isNotEmpty) {
      match.correctedCover = coverBytes;
      await CoverEnricher(settings).saveFixedCover(match, coverBytes);
    }
    notifyListeners();
  }

  Future<void> scan() async {
    // Never run two scans at once (a rescan after a download must not race the
    // startup scan over `tracks`). Coalesce concurrent requests into one re-run.
    if (scanning) {
      _rescanQueued = true;
      return;
    }
    scanning = true;
    scanned = 0;
    notifyListeners();

    // Pass 1 — tags, off the UI thread, with a timeout. A single malformed file that
    // makes readMetadata hang must NOT stall the scan forever (that left the app stuck
    // on "scannen… 0" after a download). The current library is kept intact until the
    // new scan succeeds, so a rescan never blanks the UI — the app stays usable.
    List<Map<String, dynamic>> raw;
    try {
      // Capture a plain String — NOT `this`. Referencing the instance field `rootPath`
      // directly makes the isolate closure capture the whole LibraryStore, which fails
      // to send once widgets have attached (non-sendable) listeners → the scan would
      // silently return nothing and the library shows empty.
      final root = rootPath;
      raw = await Isolate.run(() => _scanTags(root)).timeout(const Duration(seconds: 120));
    } catch (_) {
      // Timed out or failed — keep whatever library we already have loaded.
      scanning = false;
      notifyListeners();
      return;
    }
    tracks
      ..clear()
      ..addAll(raw
          .map(_trackFromMap)
          .where((t) => !_hidden.contains(t.path)) // "removed from library only" stays removed
          .map(_applyCorrection));
    scanned = tracks.length;
    _buildAlbums();
    scanning = false;
    notifyListeners();

    // Pass 2 — one embedded cover per album, off the UI thread. Guarded with a
    // timeout: a malformed file that makes readMetadata hang can never stall
    // startup (which would also block cover enrichment from ever running).
    final firstPaths = albums.map((a) => a.tracks.first.path).toList();
    try {
      final covers =
          await Isolate.run(() => _readCovers(firstPaths)).timeout(const Duration(seconds: 30));
      for (final a in albums) {
        final c = covers[a.tracks.first.path];
        if (c != null && c.isNotEmpty) a.embeddedCover = c;
      }
      notifyListeners();
    } catch (_) {
      // Timed out or failed — cached + web covers still fill in via enrich().
    }

    // A rescan requested while this one was running — run it once now.
    if (_rescanQueued) {
      _rescanQueued = false;
      await scan();
    }
  }

  Track _trackFromMap(Map<String, dynamic> m) => Track(
        path: m['path'] as String,
        title: m['title'] as String,
        artist: m['artist'] as String,
        album: m['album'] as String,
        trackNo: m['trackNo'] as int,
        duration: (m['durationMs'] as int) > 0 ? Duration(milliseconds: m['durationMs'] as int) : null,
        isFlac: m['isFlac'] as bool,
        year: m['year'] as int?,
        genre: m['genre'] as String?,
        addedMs: (m['addedMs'] as int?) ?? 0,
        sizeBytes: (m['sizeBytes'] as int?) ?? 0,
      );

  String _albumKey(String artist, String album, String firstPath) =>
      album.isEmpty ? 'single::$firstPath' : 'album::${normKey(artist)}|${normKey(album)}';

  void _buildAlbums() {
    // Snapshot the covers of the CURRENT albums, keyed by the SAME group key used below (NOT by
    // first-track path — that can change when the first track is deleted). Rebuilding makes fresh
    // Album objects with null covers, so without this ANY caller (delete, correction, …) would
    // blank the whole grid until the next scan/enrich. This is the fix for "deleting a track wipes
    // all album covers".
    final coversByKey = <String, List<Uint8List?>>{};
    for (final a in albums) {
      if (a.tracks.isEmpty) continue;
      coversByKey[_albumKey(a.artist, a.isSingle ? '' : a.title, a.tracks.first.path)] =
          [a.embeddedCover, a.enriched, a.correctedCover];
    }

    final map = <String, List<Track>>{};
    for (final t in tracks) {
      // No album tag => its own single (never grouped under the root folder name).
      // Group on NORMALISED artist+album: "Backstreet's Back" with a curly ’ and with a
      // straight ' are the same album and must not show up twice.
      map.putIfAbsent(_albumKey(t.artist, t.album, t.path), () => []).add(t);
    }
    albums = map.entries.map((e) {
      final single = e.key.startsWith('single::');
      final ts = single ? e.value : _dedupeTracks(e.value);
      ts.sort((a, b) => a.trackNo.compareTo(b.trackNo));
      final al = Album(single ? ts.first.title : ts.first.album, ts.first.artist, ts, isSingle: single);
      final saved = coversByKey[e.key];
      if (saved != null) {
        al.embeddedCover = saved[0];
        al.enriched = saved[1];
        al.correctedCover = saved[2];
      }
      return al;
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    // Rebuild the "do I already own this?" index used to skip duplicate downloads.
    _owned.clear();
    for (final t in tracks) {
      _owned.putIfAbsent(trackIdentity(t.artist, t.title), () => t);
    }

    // Rebuild the flat-track lookups (cover-per-track + path→track for resume).
    _albumByPath.clear();
    _trackByPath.clear();
    for (final a in albums) {
      for (final t in a.tracks) {
        _albumByPath[t.path] = a;
        _trackByPath[t.path] = t;
      }
    }
  }

  /// Fill missing album covers. Phase 1 loads everything already on disk (instant,
  /// can't hang); phase 2 fetches the rest from the web (each call has a timeout).
  Future<void> enrich(AppSettings settings) async {
    final enricher = CoverEnricher(settings);
    // Phase 1 — instant: on-disk cache only, no network. User-corrected covers first
    // (they win over embedded/enriched and must survive a rescan).
    for (final album in albums) {
      final fixed = await enricher.fixedCover(album);
      if (fixed != null) {
        album.correctedCover = fixed;
        continue;
      }
      if (album.cover != null) continue;
      final bytes = await enricher.cached(album);
      if (bytes != null) album.enriched = bytes;
    }
    notifyListeners();
    // Phase 2 — network fill for whatever is still missing.
    enriching = true;
    notifyListeners();
    for (final album in albums) {
      if (album.cover != null) continue;
      final bytes = await enricher.fetchAndCache(album);
      if (bytes != null) {
        album.enriched = bytes;
        notifyListeners();
      }
    }
    enriching = false;
    notifyListeners();
  }

  /// Artist photos (Deezer) + bios (TheAudioDB). Phase 1 = disk cache (instant),
  /// phase 2 = network for whatever is still missing.
  Future<void> enrichArtists(AppSettings settings) async {
    final enricher = CoverEnricher(settings);
    // Phase 1 — instant: on-disk cache only.
    for (final name in artists) {
      if (!artistImages.containsKey(name)) {
        final b = await enricher.cachedArtist(name);
        if (b != null) artistImages[name] = b;
      }
      if (!artistBios.containsKey(name)) {
        final bio = await enricher.cachedBio(name);
        if (bio != null) artistBios[name] = bio;
      }
    }
    notifyListeners();
    // Phase 2 — network fill.
    for (final name in artists) {
      if (!artistImages.containsKey(name)) {
        final b = await enricher.fetchArtistImage(name);
        if (b != null) { artistImages[name] = b; notifyListeners(); }
      }
      if (!artistBios.containsKey(name)) {
        final bio = await enricher.fetchArtistBio(name);
        if (bio != null) { artistBios[name] = bio; notifyListeners(); }
      }
    }
  }

  List<String> get artists {
    final set = <String>{};
    for (final a in albums) {
      set.add(a.artist);
    }
    final list = set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }
}
