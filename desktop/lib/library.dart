import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'enrichment.dart';
import 'models.dart';
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

    // Preserve already-loaded covers across the regroup. _buildAlbums() creates fresh
    // Album objects, so without this every album's embedded/enriched cover is dropped
    // (only the corrected album carries a correctedCover) and the whole grid goes blank
    // until the next scan/enrich. Keyed by first-track path, which is stable per album.
    final coversByPath = <String, List<Uint8List?>>{};
    for (final a in albums) {
      coversByPath[a.tracks.first.path] = [a.embeddedCover, a.enriched, a.correctedCover];
    }

    // Re-apply corrections to the in-memory tracks + regroup.
    final corrected = tracks.map(_applyCorrection).toList();
    tracks
      ..clear()
      ..addAll(corrected);
    _buildAlbums();

    // Restore the preserved covers onto the rebuilt albums.
    for (final a in albums) {
      final saved = coversByPath[a.tracks.first.path];
      if (saved != null) {
        a.embeddedCover ??= saved[0];
        a.enriched ??= saved[1];
        a.correctedCover ??= saved[2];
      }
    }

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
      ..addAll(raw.map(_trackFromMap).map(_applyCorrection));
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
      );

  void _buildAlbums() {
    final map = <String, List<Track>>{};
    for (final t in tracks) {
      // No album tag => its own single (never grouped under the root folder name).
      final key = t.album.isEmpty
          ? 'single::${t.path}'
          : 'album::${t.artist.toLowerCase()}|${t.album.toLowerCase()}';
      map.putIfAbsent(key, () => []).add(t);
    }
    albums = map.entries.map((e) {
      final ts = e.value..sort((a, b) => a.trackNo.compareTo(b.trackNo));
      final single = e.key.startsWith('single::');
      return Album(single ? ts.first.title : ts.first.album, ts.first.artist, ts, isSingle: single);
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

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
