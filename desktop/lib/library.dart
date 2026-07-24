import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'editions.dart';
import 'enrichment.dart';
import 'flac_tags.dart';
import 'lan/client.dart';
import 'lan/dtos.dart';
import 'models.dart';
import 'organize.dart';
import 'settings.dart';
import 'paths.dart';

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
    // Skip the download staging folder. Files in there are still arriving — a half-finished 2 MB
    // WAV was showing up as its own album, 0:00 long, until the transfer completed.
    if (e.path.contains('${Platform.pathSeparator}_inkomend${Platform.pathSeparator}')) continue;
    // Skip the parking folder for superseded copies. They are kept on disk as a safety net but are
    // deliberately NOT part of the library — otherwise a parked junk WAV keeps scanning back in as
    // its own single and the duplicate cleanup can never finish.
    if (e.path.contains('${Platform.pathSeparator}$dupeFolder${Platform.pathSeparator}')) continue;
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
          'trackTotal': v.trackTotal,
          'durationMs': v.duration?.inMilliseconds ?? 0,
          'isFlac': true,
          'year': v.year,
          'genre': v.genre,
          'addedMs': addedMs,
          'sizeBytes': sizeBytes,
          'sampleRate': v.sampleRate,
          'bitsPerSample': v.bitsPerSample,
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
        // The generic reader has no track-total, so a non-FLAC file simply doesn't take part in
        // edition splitting — it stays with the plain album, which is where it was anyway.
        'trackTotal': 0,
        'durationMs': m.duration?.inMilliseconds ?? 0,
        'isFlac': _ext(e.path) == '.flac',
        'year': (m.year != null && m.year!.year > 1000) ? m.year!.year : null,
        'genre': (m.genres.isNotEmpty) ? m.genres.first : null,
        'addedMs': addedMs,
        'sizeBytes': sizeBytes,
        'sampleRate': m.sampleRate ?? 0,
        // The generic reader doesn't report bit depth; only the FLAC path above can.
        'bitsPerSample': 0,
      });
    } catch (_) {}
  }
  return out;
}

/// Run pass 1 on another isolate.
///
/// The `Isolate.run` closure is built HERE, at top level, and deliberately not inside
/// [LibraryStore.scan]. A closure created inside an instance method carries its enclosing
/// context with it, and that context reaches both `this` and the async method's own completer.
/// Once a widget has attached a listener to the store, that context is unsendable: the send
/// throws, the scan's catch swallows it, and the app comes up with an EMPTY LIBRARY while the
/// music sits untouched on disk. Assigning `rootPath` to a local first is not enough to prevent
/// it — only moving the closure out of the method is.
///
/// Covered by `test/library_isolate_test.dart`, which scans with a listener attached.
Future<List<Map<String, dynamic>>> scanTagsInIsolate(String root) =>
    Isolate.run(() => _scanTags(root));

/// Pass 2 on another isolate — same reasoning as [scanTagsInIsolate].
Future<Map<String, Uint8List>> readCoversInIsolate(List<String> paths) =>
    Isolate.run(() => _readCovers(paths));

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

  /// Albums/singles found to be entirely duplicates of a real album you own — recomputed after each
  /// full scan, so the library can offer to tidy them without the user going hunting. Empty until a
  /// scan has run. See the [LibraryDuplicates] extension.
  List<RedundantAlbum> duplicates = const [];

  /// Recompute [duplicates]. In its own method so the extension can be reached from [scan].
  void _recomputeDuplicates() {
    try {
      duplicates = redundantAlbums();
    } catch (_) {
      duplicates = const []; // never let duplicate-hunting break a scan
    }
  }

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
      // Same order as filing uses: format, then stereo over surround, then size — otherwise the
      // album view would show the 5.1 rip while the folder keeps the stereo master.
      if (firstIsBetter(File(t.path), File(cur.path))) best[id] = t;
    }
    return best.values.toList();
  }
  final Map<String, Track> _trackByPath = {};

  /// The album cover for a track (covers live on the Album, not the Track).
  Uint8List? coverForTrack(Track t) => _albumByPath[t.path]?.cover;

  /// The album a playing track belongs to. The now-playing screen needs the album, not just the
  /// track: the pressing the user pinned and the cover they picked both live on it, and without
  /// them that screen went off and resolved its own record — landing on a different artist's album
  /// that happened to share a title.
  Album? albumForPath(String path) => _albumByPath[path];

  /// Resolve a saved file path back to a library track (for resume).
  Track? trackByPath(String path) => _trackByPath[path];

  // Manual metadata corrections (non-destructive): file path -> {title,artist,album}.
  // Applied to scanned tracks so wrong tags are fixed without touching the files.
  final Map<String, Map<String, String>> _corrections = {};

  /// Where this app keeps its own files. Overridable ONLY so a test can be given a scratch folder:
  /// corrections.json is the user's hand-made metadata, and a test run that wrote its two fixtures
  /// over the real one would destroy months of edits.
  @visibleForTesting
  String? configDirOverride;

  String get _appDir {
    final o = configDirOverride;
    if (o != null) return o;
    return appDir;
  }

  /// What is recorded against a file, or null. For tests.
  @visibleForTesting
  Map<String, String>? correctionForTest(String path) => _corrections[path];

  /// Record something against a file, as an earlier edit would have. For tests.
  @visibleForTesting
  void seedCorrectionForTest(String path, Map<String, String> c) => _correctionsFor(path).addAll(c);

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

  // ── Merged editions ───────────────────────────────────────────────────────
  // Splitting is a guess made from tags; merging is the user telling us the guess was wrong.
  // Their word is final and has to outlive a rescan, so it is written down like every other
  // correction rather than held in memory.
  final Set<String> _merged = {};
  File get _mergedFile => File('$_appDir${Platform.pathSeparator}merged_albums.json');

  Future<void> loadMerged() async {
    try {
      final f = _mergedFile;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as List<dynamic>;
      _merged
        ..clear()
        ..addAll(j.map((e) => e.toString()));
    } catch (_) {}
  }

  Future<void> _saveMerged() async {
    try {
      await Directory(_appDir).create(recursive: true);
      await _mergedFile.writeAsString(jsonEncode(_merged.toList()));
    } catch (_) {}
  }

  /// Put every edition of this record back together, and keep it that way.
  Future<void> mergeEditions(Album a) async {
    if (isRemote) return _editOnPc({'op': 'merge', 'albumId': remoteAlbumId(a)});
    _merged.add('album::${artistKey(a.artist)}|${normKey(a.title)}');
    await _saveMerged();
    rebuildAlbums();
    notifyListeners();
  }

  /// Undo that, and let the tags decide again.
  Future<void> unmergeEditions(Album a) async {
    if (isRemote) return _editOnPc({'op': 'unmerge', 'albumId': remoteAlbumId(a)});
    _merged.remove('album::${artistKey(a.artist)}|${normKey(a.title)}');
    await _saveMerged();
    rebuildAlbums();
    notifyListeners();
  }

  /// Has the user told us to keep this record together?
  bool isMerged(Album a) => _merged.contains('album::${artistKey(a.artist)}|${normKey(a.title)}');

  /// The exact Discogs release the user pinned to this album, if they pinned one.
  ///
  /// Their choice is the source for everything after it — edition, label, catalogue number, back
  /// cover and disc — instead of the app going off and picking its own pressing, which is why a
  /// correction changed the front cover and nothing else.
  int? pinnedRelease(Album a) {
    for (final t in a.tracks) {
      final id = int.tryParse(_corrections[t.path]?['release'] ?? '');
      if (id != null && id > 0) return id;
    }
    return null;
  }

  /// The MusicBrainz pressing the user pinned, if they pinned one there instead.
  ///
  /// Its own key rather than sharing [pinnedRelease]'s: an MBID is a string and a Discogs id is a
  /// number, and every pin already written to disk is a number. One key for both would have made
  /// those unreadable the first time this shipped.
  String? pinnedMbid(Album a) {
    for (final t in a.tracks) {
      final id = _corrections[t.path]?['mbid'];
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  // ── Chosen artist art ─────────────────────────────────────────────────────
  // Which portrait and which backdrop the user picked for an artist. Kept beside the other
  // corrections for the same reason: the choice has to outlive a rescan, and must never be quietly
  // replaced by whatever an automatic source turns up next.
  final Map<String, Map<String, String>> _artistArtChoice = {};
  File get _artistArtChoiceFile => File('$_appDir${Platform.pathSeparator}artist_art_choice.json');

  Future<void> loadArtistArtChoice() async {
    try {
      final f = _artistArtChoiceFile;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _artistArtChoice.clear();
      j.forEach((k, v) {
        if (v is Map) _artistArtChoice[k] = v.map((a, b) => MapEntry(a.toString(), b.toString()));
      });
    } catch (_) {}
  }

  /// The image URL the user picked for [kind] — 'portrait' or 'backdrop' — or null.
  String? chosenArtistArt(String artist, String kind) => _artistArtChoice[artistKey(artist)]?[kind];

  Future<void> setArtistArt(String artist, String kind, String url) async {
    _artistArtChoice.putIfAbsent(artistKey(artist), () => {})[kind] = url;
    try {
      await Directory(_appDir).create(recursive: true);
      await _artistArtChoiceFile.writeAsString(jsonEncode(_artistArtChoice));
    } catch (_) {}
    notifyListeners();
  }

  // ── Styles ────────────────────────────────────────────────────────────────
  // A Discogs style is far finer than a genre: an album is not just "Electronic" but "House,
  // Disco, Synth-pop". That is what makes browsing by feel possible instead of by category, so
  // styles are remembered as albums are opened and the map fills in as the app gets used.
  final Map<String, List<String>> _styles = {};
  File get _stylesFile => File('$_appDir${Platform.pathSeparator}album_styles.json');

  Future<void> loadStyles() async {
    try {
      final f = _stylesFile;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _styles.clear();
      j.forEach((k, v) {
        if (v is List) _styles[k] = [for (final x in v) x.toString()];
      });
    } catch (_) {}
  }

  String _styleKey(String artist, String album) => '${artistKey(artist)}|${normKey(album)}';

  List<String> stylesOf(Album a) => _styles[_styleKey(a.artist, a.title)] ?? const [];

  /// Remember what a record sounds like, found while its page was open.
  Future<void> rememberStyles(String artist, String album, List<String> styles) async {
    if (styles.isEmpty) return;
    final k = _styleKey(artist, album);
    if (_styles[k]?.join() == styles.join()) return;
    _styles[k] = styles;
    try {
      await Directory(_appDir).create(recursive: true);
      await _stylesFile.writeAsString(jsonEncode(_styles));
    } catch (_) {}
    notifyListeners();
  }

  /// Every style seen so far, most common first — the vocabulary this library actually uses.
  List<MapEntry<String, int>> styleTally() {
    final n = <String, int>{};
    for (final a in albums) {
      for (final st in stylesOf(a)) {
        n.update(st, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final out = n.entries.toList();
    out.sort((x, y) => y.value.compareTo(x.value));
    return out;
  }

  /// The albums that share a style.
  List<Album> albumsWithStyle(String style) =>
      albums.where((a) => stylesOf(a).any((s) => s.toLowerCase() == style.toLowerCase())).toList();

  /// Hand the library a cover found while an album page was open.
  ///
  /// The album page draws its own sleeve from Discogs, so a wrong embedded cover was corrected
  /// there and nowhere else: opening the album showed the right art, going back to the grid
  /// showed the old one. Now the correction reaches the library the moment it is found.
  ///
  /// Stored as the ENRICHED cover, never over one the user picked by hand.
  void adoptAlbumCover(String artist, String album, Uint8List bytes) {
    if (bytes.length < 500) return;
    var changed = false;
    for (final a in albums) {
      if (a.tracks.isEmpty) continue;
      if (artistKey(a.artist) != artistKey(artist) || normKey(a.title) != normKey(album)) continue;
      if (a.correctedCover != null) continue;
      if (identical(a.enriched, bytes)) continue;
      a.enriched = bytes;
      changed = true;
    }
    if (changed) notifyListeners();
  }

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
    if (isRemote) {
      final ids = [
        for (final p in paths)
          if (_remoteTrackId(p) case final id?) id,
      ];
      await _editOnPc({'op': 'removeTracks', 'trackIds': ids, 'fromDisk': fromDisk});
      // What the PC deleted from disk is its count to give; the caller only shows it.
      return fromDisk ? ids.length : 0;
    }
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
    rebuildAlbums();
    notifyListeners();
    return deleted;
  }

  Future<void> loadCorrections() async {
    try {
      final f = _correctionsFile;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _corrections.clear();
      var orphans = 0;
      for (final e in j.entries) {
        final path = e.key, v = e.value;
        if (v is! Map) continue;
        // Drop a correction whose file is gone. An album moved or re-ripped leaves its old
        // corrections behind as orphans, and they cause real confusion: Adele's 30 had fifteen
        // live pins under one folder and fifteen dead, empty ones under a deleted Japanese edition,
        // and reading the wrong list made the pin look empty when it was not.
        if (!File(path).existsSync()) {
          orphans++;
          continue;
        }
        _corrections[path] = v.map((k, val) => MapEntry(k.toString(), val.toString()));
      }
      // Persist the cleanup, but only when there was something to clean — no pointless rewrite.
      if (orphans > 0) await _saveCorrections();
    } catch (_) {}
  }

  /// The correction map for a path, created on demand — so an extension can add to it.
  Map<String, String> _correctionsFor(String path) => _corrections.putIfAbsent(path, () => {});

  /// Carry a file's corrections to where the file now is.
  ///
  /// Corrections are keyed by absolute path, so a move silently orphans them: the entry stays under
  /// the old name, [_applyCorrection] looks under the new one and finds nothing, and
  /// [loadCorrections] deletes it as a dead file at the next start. A track moved into another
  /// album would end up with its FILE in the new folder and its GROUPING back in the old one —
  /// worse than either half alone, and it would have taken the album's pinned release with it.
  void _reKeyCorrection(String from, String to) {
    if (from == to) return;
    final old = _corrections.remove(from);
    if (old == null || old.isEmpty) return;
    _corrections.putIfAbsent(to, () => {}).addAll(old);
  }

  /// Public save, for the move extension.
  Future<void> saveCorrectionsNow() => _saveCorrections();

  /// Re-apply every correction to the in-memory tracks and regroup.
  ///
  /// Public because the extensions in this file write corrections and then need the library to
  /// reflect them; notifyListeners is protected, so an extension cannot do the last step itself.
  void refreshFromCorrections() {
    final corrected = tracks.map(_applyCorrection).toList();
    tracks
      ..clear()
      ..addAll(corrected);
    rebuildAlbums();
    notifyListeners();
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
      // A number taken from an official pressing. The tags are what these override: a ripper that
      // wrote two number sixes and left a track blank is exactly the case this exists for.
      trackNo: int.tryParse(c['trackNo'] ?? '') ?? t.trackNo,
      trackTotal: int.tryParse(c['trackTotal'] ?? '') ?? t.trackTotal,
      duration: t.duration,
      isFlac: t.isFlac,
      year: t.year,
      genre: t.genre,
      addedMs: t.addedMs,
      sizeBytes: t.sizeBytes,
      sampleRate: t.sampleRate,
      bitsPerSample: t.bitsPerSample,
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
    int? discogsRelease,
    String? mbid,
  }) async {
    if (isRemote) {
      return _editOnPc({
        'op': 'correction',
        'albumId': remoteAlbumId(target),
        'artist': artist,
        'albumTitle': albumTitle,
        'title': title,
        if (coverBytes != null && coverBytes.isNotEmpty) 'cover': base64Encode(coverBytes),
        'discogsRelease': discogsRelease,
        'mbid': mbid,
      });
    }
    for (final t in target.tracks) {
      final c = _corrections.putIfAbsent(t.path, () => {});
      // Discogs numbers artists who share a name and asterisks name variants; neither belongs in
      // a library, let alone on the now-playing bar.
      if (artist != null && artist.trim().isNotEmpty) c['artist'] = cleanArtistName(artist);
      if (albumTitle != null && albumTitle.trim().isNotEmpty && !target.isSingle) {
        c['album'] = albumTitle.trim();
      }
      if (title != null && title.trim().isNotEmpty && target.isSingle) c['title'] = title.trim();
      // The exact pressing the user pointed at. Everything else about this album — its edition
      // line, its back cover, its disc — is read from this one release from now on, instead of
      // whichever the app would have picked for itself.
      if (discogsRelease != null && discogsRelease > 0) c['release'] = '$discogsRelease';
      // Picking from a different source replaces the pin rather than layering on top of it: two
      // pressings pinned at once is not a state anything downstream could read sensibly.
      if (mbid != null && mbid.isNotEmpty) {
        c['mbid'] = mbid;
        c.remove('release');
      } else if (discogsRelease != null && discogsRelease > 0) {
        c.remove('mbid');
      }
    }
    await _saveCorrections();

    // Re-apply corrections to the in-memory tracks + regroup. rebuildAlbums() preserves each
    // album's covers across the rebuild, so the grid no longer blanks here.
    final corrected = tracks.map(_applyCorrection).toList();
    tracks
      ..clear()
      ..addAll(corrected);
    rebuildAlbums();

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
      raw = await scanTagsInIsolate(rootPath).timeout(const Duration(seconds: 120));
    } catch (e) {
      // Timed out or failed — keep whatever library we already have loaded. Reported rather
      // than swallowed: this exact failure was silent for a long time, and a silent scan
      // failure is indistinguishable from an empty music folder.
      debugPrint('Library scan failed: $e');
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
    rebuildAlbums();
    scanning = false;
    // Look for albums that are wholly duplicates of one you already own. Only after a full scan —
    // it reads file sizes and headers, too heavy to redo on every regroup.
    _recomputeDuplicates();
    notifyListeners();

    // Pass 2 — one embedded cover per album, off the UI thread. Guarded with a
    // timeout: a malformed file that makes readMetadata hang can never stall
    // startup (which would also block cover enrichment from ever running).
    final firstPaths = albums.map((a) => a.tracks.first.path).toList();
    try {
      final covers = await readCoversInIsolate(firstPaths).timeout(const Duration(seconds: 30));
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

  // ── Client mode: the library comes from a paired PC ────────────────────────
  //
  // The dividing line in this app is not Windows versus Apple, it is "does this device hold the
  // music?". A Mac and an iPad do not, so instead of walking a folder they read /api/catalog from
  // the Windows PC. Everything above this line — every screen, every sort, every cover — is
  // unchanged, because what lands in [tracks] and [albums] is the same shape either way.

  RemoteClient? _remote;

  /// The paired PC, or null on the machine that owns the music.
  RemoteClient? get remote => _remote;

  /// True when this app is reading someone else's library. Screens that WRITE check this.
  bool get isRemote => _remote != null;

  /// The catalogue's ETag from last time, so a poll that finds nothing changed costs one 304
  /// instead of re-sending twelve thousand tracks.
  String? _catalogEtag;

  set remote(RemoteClient? client) {
    _remote = client;
    _catalogEtag = null;
  }

  /// Fill the library from the paired PC. The counterpart of [scan].
  ///
  /// Returns true when something actually changed, so a caller polling this can skip the work that
  /// follows a real update.
  ///
  /// The album grouping is ADOPTED from the PC, not recomputed here. That is the whole point: the
  /// PC has already split editions, applied the corrections you typed and honoured the pressings
  /// you pinned, and re-deriving any of that from tags would be a second implementation that
  /// drifts. Whatever you see on the PC is what lands here, including next year's grouping rule.
  Future<bool> loadRemote({bool quiet = false}) async {
    final client = _remote;
    if (client == null) return false;
    if (scanning) {
      _rescanQueued = true;
      return false;
    }
    scanning = !quiet;
    if (!quiet) notifyListeners();

    CatalogResponse res;
    try {
      res = await client.catalog(etag: _catalogEtag);
    } catch (e) {
      // Keep the library we already have. A Mac that loses the PC mid-song should keep showing the
      // record it is playing, not blank the screen — the same reasoning as a failed disk scan.
      debugPrint('Remote catalog failed: $e');
      scanning = false;
      notifyListeners();
      return false;
    }
    _catalogEtag = res.etag;
    final catalog = res.catalog;
    if (catalog == null) {
      scanning = false;
      if (!quiet) notifyListeners();
      return false;
    }

    _adoptCatalog(catalog, client);
    scanned = tracks.length;
    scanning = false;
    notifyListeners();

    if (_rescanQueued) {
      _rescanQueued = false;
      await loadRemote(quiet: quiet);
    }
    return true;
  }

  /// Turn what the PC sent into the very same [Track] and [Album] objects a disk scan produces.
  void _adoptCatalog(CatalogDto catalog, RemoteClient client) {
    // Covers, keyed by track path exactly as [rebuildAlbums] does — a refreshed catalogue makes
    // fresh Album objects, and without this the grid blanks on every poll and then refetches every
    // cover over the network.
    final coversByPath = <String, List<Uint8List?>>{};
    for (final a in albums) {
      final snap = [a.embeddedCover, a.enriched, a.correctedCover];
      for (final t in a.tracks) {
        coversByPath[t.path] = snap;
      }
    }

    final byAlbum = <String, List<Track>>{};
    tracks.clear();
    for (final dto in catalog.tracks) {
      final t = _trackFromDto(dto, client);
      tracks.add(t);
      byAlbum.putIfAbsent(dto.albumId, () => []).add(t);
    }

    _rebuildCanonicalArtists();

    final built = <Album>[];
    _remoteAlbums.clear();
    for (final dto in catalog.albums) {
      final ts = byAlbum[dto.id];
      // An album whose every track was filtered out (hidden on the PC) is not an album.
      if (ts == null || ts.isEmpty) continue;
      ts.sort((a, b) => a.trackNo.compareTo(b.trackNo));
      final al = Album(dto.title, dto.artistName, ts, isSingle: dto.isSingle)
        ..edition = dto.edition;
      for (final t in ts) {
        final saved = coversByPath[t.path];
        if (saved == null) continue;
        al.embeddedCover = saved[0];
        al.enriched = saved[1];
        al.correctedCover = saved[2];
        break;
      }
      _remoteAlbums[al] = (id: dto.id, artRef: dto.artworkRef ?? dto.id);
      built.add(al);
    }
    albums = built..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    _rebuildTrackIndexes();
  }

  /// What the PC calls each album we are showing: its id (for a write, in phase C) and the
  /// reference to ask `/art/` for. Keyed by object identity — [Album] has no value equality, and a
  /// refreshed catalogue makes new ones, so this is cleared and refilled with them.
  final Map<Album, ({String id, String artRef})> _remoteAlbums = {};

  /// The PC's id for an album we are showing, or null on the machine that owns the music.
  String? remoteAlbumId(Album a) => _remoteAlbums[a]?.id;

  /// True everywhere now: a Mac and an iPad edit by asking the PC to, and the result comes back
  /// through the catalogue. Kept as a name rather than inlined, because moving files is still the
  /// PC's alone and this is where that line would move if it ever changes.
  bool get canEdit => true;

  /// Hand an edit to the PC and take its answer as the truth.
  ///
  /// Nothing is changed locally first. The PC applies it to the library everyone reads, the
  /// catalogue fingerprint moves, and [loadRemote] brings back the result — including whatever the
  /// PC decided that we did not, like a regroup that follows from a corrected track count. Editing
  /// optimistically here would mean guessing at that, and being wrong in exactly the cases the
  /// user is trying to fix.
  Future<void> _editOnPc(Map<String, dynamic> operation) async {
    final client = _remote;
    if (client == null) return;
    await client.edit(operation);
    // Straight away rather than on the next poll: the screen that asked is still open, and a
    // correction that takes fifteen seconds to appear reads as one that did not work.
    _catalogEtag = null;
    await loadRemote(quiet: true);
  }

  /// The PC's id for a track we are showing. Its path is the stream URL, and the id is in it.
  String? _remoteTrackId(String path) {
    final segments = Uri.tryParse(path)?.pathSegments ?? const [];
    if (segments.length < 2 || segments[segments.length - 2] != 'stream') return null;
    final last = segments.last;
    final dot = last.lastIndexOf('.');
    return dot < 0 ? last : last.substring(0, dot);
  }

  /// A track as the PC describes it. [Track.path] becomes the stream URL WITHOUT the token: it is
  /// the identity key for favourites, playlists and resume, and those must survive re-pairing —
  /// the token is added at the moment of playback instead. The extension is kept because that is
  /// how a player types the stream.
  Track _trackFromDto(TrackDto d, RemoteClient client) => Track(
        path: client.endpoint.baseUrl.replace(path: d.streamPath).toString(),
        title: d.title,
        artist: d.artistName,
        album: d.albumTitle,
        trackNo: d.trackNo,
        trackTotal: d.trackTotal,
        duration: d.durationMs > 0 ? Duration(milliseconds: d.durationMs) : null,
        isFlac: d.ext == 'flac',
        year: d.year,
        genre: d.genre,
        addedMs: d.addedMs,
        sizeBytes: d.sizeBytes,
        sampleRate: d.sampleRate ?? 0,
        bitsPerSample: d.bitsPerSample ?? 0,
      );

  /// Covers, over the network, after the grid is already on screen.
  ///
  /// The disk cache is [CoverEnricher]'s own, keyed by artist+title rather than by path, so a Mac
  /// that has seen a record once shows its cover instantly on the next start — and pays for the
  /// fetch only the first time. Deliberately not part of [loadRemote]: the library should appear
  /// immediately, with the covers filling in behind it, rather than the screen staying empty until
  /// the last one has arrived.
  Future<void> loadRemoteCovers(AppSettings settings) async {
    final client = _remote;
    if (client == null) return;
    final enricher = CoverEnricher(settings);
    enriching = true;
    notifyListeners();
    var since = 0;
    for (final album in albums) {
      if (album.cover != null) continue;
      final cached = await enricher.cached(album);
      if (cached != null) {
        album.enriched = cached;
        if (++since >= 24) {
          since = 0;
          notifyListeners();
        }
        continue;
      }
      final ref = _remoteAlbums[album]?.artRef;
      final bytes = ref == null ? null : await client.art(ref);
      if (bytes == null || bytes.isEmpty) continue;
      album.embeddedCover = bytes;
      await enricher.putCached(album, bytes);
      notifyListeners();
    }
    enriching = false;
    notifyListeners();
  }

  Track _trackFromMap(Map<String, dynamic> m) => Track(
        path: m['path'] as String,
        title: m['title'] as String,
        artist: m['artist'] as String,
        album: m['album'] as String,
        trackNo: m['trackNo'] as int,
        trackTotal: (m['trackTotal'] as int?) ?? 0,
        duration: (m['durationMs'] as int) > 0 ? Duration(milliseconds: m['durationMs'] as int) : null,
        isFlac: m['isFlac'] as bool,
        year: m['year'] as int?,
        genre: m['genre'] as String?,
        addedMs: (m['addedMs'] as int?) ?? 0,
        sizeBytes: (m['sizeBytes'] as int?) ?? 0,
        sampleRate: (m['sampleRate'] as int?) ?? 0,
        bitsPerSample: (m['bitsPerSample'] as int?) ?? 0,
      );

  /// Which album a TRACK belongs to. Derived from the track's own tags, never from an Album's
  /// displayed artist: the two drifted apart once "Nunca feat. Pat Krimson" started displaying as
  /// "Nunca", and the cover snapshot below — stored under one and looked up under the other —
  /// silently dropped that album's covers on every regroup, including a hand-picked one.
  /// Both the snapshot and the grouping go through here so they cannot diverge again.
  /// Which album a track belongs to.
  ///
  /// Artist and title alone merged two EDITIONS of one record: a single Backstreet Boys folder held
  /// tracks claiming 12, 16 and 13 tracks total, so the page showed two number sixes, two number
  /// tens, and "Quit Playing Games" twice. The track total is the one tag that separates them.
  ///
  /// Only when a track total is actually stated. Files without one — untagged rips, and everything
  /// that isn't FLAC, since the generic reader doesn't report it — stay on the plain album key
  /// exactly as before. Guessing which edition those belong to would scatter a library, and being
  /// wrong there is worse than the merging this fixes.
  String _groupKey(Track t) {
    if (t.album.isEmpty) return 'single::${t.path}';
    final base = 'album::${artistKey(t.artist)}|${normKey(t.album)}';
    // The user's word beats the tags: a record they merged stays merged.
    if (_merged.contains(base)) return base;
    return editionSplit(_byBase[base]) ? '$base|${t.trackTotal}' : base;
  }

  /// Tracks of one artist+album title, kept so [_groupKey] can ask whether that title needs
  /// splitting before it answers for any single track.
  final Map<String, List<Track>> _byBase = {};

  /// Every track filed under one artist+title, whatever edition it belongs to.
  List<Track>? editionsOfRecord(String baseKey) => _byBase[baseKey];

  /// Does this pile of tracks hold more than one EDITION of the record?
  ///
  /// Splitting on the stated track total alone was far too eager: every ripper writes its own, so
  /// one artist came out with six identical "Backstreet Boys" tiles, three "Backstreet's Back" and
  /// two "Black & Blue" — worse to look at than the merging it was meant to fix.
  ///
  /// So split only where merging actually breaks something: two tracks claiming the SAME number.
  /// That is the symptom — two number tens, two number sixes, "Quit Playing Games" listed twice —
  /// and where it doesn't happen, differing totals are just sloppy tagging and are left alone.
  static bool editionSplit(List<Track>? group) {
    if (group == null || group.length < 2) return false;
    final seen = <int>{};
    for (final t in group) {
      if (t.trackNo > 0 && !seen.add(t.trackNo)) {
        // A collision. Only worth splitting if the totals can actually separate them.
        // Zero counts as its own edition here: an untagged rip that collides with a tagged one is
        // demonstrably not from the same pressing, whatever it forgot to say.
        return group.map((x) => x.trackTotal).toSet().length > 1;
      }
    }
    return false;
  }

  /// Regroup tracks into albums. Public so a test can reproduce the "edit one album, another
  /// album loses its cover" regression without going through the on-disk correction path.
  void rebuildAlbums() {
    // Which titles hold more than one edition has to be known BEFORE any track is keyed, including
    // for the cover snapshot below — the two must never disagree about where an album lives.
    _byBase.clear();
    for (final t in tracks) {
      if (t.album.isEmpty) continue;
      _byBase.putIfAbsent('album::${artistKey(t.artist)}|${normKey(t.album)}', () => []).add(t);
    }

    // Snapshot the covers of the CURRENT albums. Rebuilding makes fresh Album objects with null
    // covers, so without this ANY caller (delete, correction, …) would blank the grid until the
    // next scan/enrich. This is the fix for "deleting a track wipes all album covers".
    //
    // Keyed by TRACK PATH, not by group key. The group key is exactly what a regroup changes, so
    // keying on it lost the covers of any album that moved — and correcting a record's numbering
    // moves it by definition: repairing the duplicate numbers is what makes editionSplit() stop
    // splitting, which is the whole point and would have blanked the record it just fixed.
    final coversByPath = <String, List<Uint8List?>>{};
    for (final a in albums) {
      if (a.tracks.isEmpty) continue;
      final snap = [a.embeddedCover, a.enriched, a.correctedCover];
      for (final t in a.tracks) {
        coversByPath[t.path] = snap;
      }
    }

    final canonical = _rebuildCanonicalArtists();

    final map = <String, List<Track>>{};
    for (final t in tracks) {
      // No album tag => its own single (never grouped under the root folder name).
      // Group on NORMALISED artist+album: "Backstreet's Back" with a curly ’ and with a
      // straight ' are the same album and must not show up twice.
      map.putIfAbsent(_groupKey(t), () => []).add(t);
    }
    albums = map.entries.map((e) {
      final single = e.key.startsWith('single::');
      final ts = single ? e.value : _dedupeTracks(e.value);
      ts.sort((a, b) => a.trackNo.compareTo(b.trackNo));
      final main = splitFeatured(ts.first.artist, ts.first.title).main;
      final artist = canonical[artistKey(main)] ?? main;
      final al = Album(single ? ts.first.title : ts.first.album, artist, ts, isSingle: single);
      // Only where the title actually split — a lone album needs no edition label.
      if (!single && editionSplit(_byBase['album::${artistKey(ts.first.artist)}|${normKey(ts.first.album)}'])) {
        final n = ts.first.trackTotal;
        al.edition = n > 0 ? '$n nummers' : 'zonder nummering';
      }
      // Any of this album's tracks will do — they all carried the same snapshot. Taking the first
      // that still has one survives a track being deleted or moved out from under it.
      for (final t in ts) {
        final saved = coversByPath[t.path];
        if (saved == null) continue;
        al.embeddedCover = saved[0];
        al.enriched = saved[1];
        al.correctedCover = saved[2];
        break;
      }
      return al;
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    _rebuildTrackIndexes();
  }

  /// ONE spelling per artist. Tags disagree about capitalisation and accents ("Lady Gaga" vs
  /// "Lady GaGa", "Beyoncé" vs "Beyonce"), which used to put the same person in the artist list
  /// twice. Count every spelling across the whole library and show the best one everywhere.
  /// The MAIN artist, not the full credit: "Lady Gaga feat. Beyoncé" is a Lady Gaga track and
  /// belongs on her album — Beyoncé is a guest, not a separate act in your artist list.
  ///
  /// Shared with client mode ([loadRemote]) rather than repeated there: it decides what the artist
  /// list is called, and two copies of that rule would eventually disagree about one artist and be
  /// very hard to see.
  Map<String, String> _rebuildCanonicalArtists() {
    final spellings = <String, Map<String, int>>{};
    for (final t in tracks) {
      final main = splitFeatured(t.artist, t.title).main;
      spellings
          .putIfAbsent(artistKey(main), () => <String, int>{})
          .update(main, (n) => n + 1, ifAbsent: () => 1);
    }
    final canonical = {for (final e in spellings.entries) e.key: canonicalName(e.value)};
    _canonicalArtists
      ..clear()
      ..addAll(canonical);
    return canonical;
  }

  /// The lookups every screen reads: "do I already own this?" (skips duplicate downloads), and
  /// path → album/track (cover per track, and resuming where you left off). Also shared with
  /// client mode, where the paths are stream URLs instead of files.
  void _rebuildTrackIndexes() {
    _owned.clear();
    for (final t in tracks) {
      _owned.putIfAbsent(trackIdentity(t.artist, t.title), () => t);
    }
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

  /// artistKey → the one spelling we show. A Track keeps whatever its tag says (replacing Track
  /// objects would break the player's identity checks), so anything that DISPLAYS a track's
  /// artist runs it through [displayArtist] to stay consistent with the artist list.
  final Map<String, String> _canonicalArtists = {};

  String displayArtist(String raw) {
    final main = splitFeatured(raw, '').main;
    return _canonicalArtists[artistKey(main)] ?? main;
  }

  /// True if this name is an artist you actually own — decides whether tapping it can show a
  /// local page or has to go to the online catalogue.
  bool hasArtist(String name) => _canonicalArtists.containsKey(artistKey(name));

  List<String> get artists {
    final set = <String>{};
    for (final a in albums) {
      set.add(a.artist);
    }
    final list = set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }
}

/// What taking an official pressing's numbering would do to one track.
class RenumberStep {
  final Track track;

  /// What the pressing says this track is. Null when nothing on the pressing matched it — then the
  /// track keeps its tags, which is the only safe answer.
  final ChoiceTrack? official;
  final int? newNo;
  const RenumberStep(this.track, this.official, this.newNo);

  bool get changes => newNo != null && (newNo != track.trackNo || (official?.title ?? track.title) != track.title);
  bool get unmatched => official == null;
}

/// Everything taking a pressing's numbering would do, so it can be read before it is done.
class RenumberPlan {
  final List<RenumberStep> steps;

  /// The total the pressing states, written alongside so edition splitting stops seeing a record
  /// whose tracks disagree about how long it is.
  final int total;
  const RenumberPlan(this.steps, this.total);

  List<RenumberStep> get changing => steps.where((s) => s.changes).toList();
  List<RenumberStep> get unmatched => steps.where((s) => s.unmatched).toList();

  /// Two tracks landing on one number. Refused rather than applied: the numbering is being fixed
  /// BECAUSE it collides, and swapping one collision for another helps nobody.
  bool get collides {
    final seen = <int>{};
    for (final s in steps) {
      final n = s.newNo;
      if (n != null && !seen.add(n)) return true;
    }
    return false;
  }

  /// Two tracks ending up with one title. [LibraryStore._dedupeTracks] keys on artist+title, so
  /// this would not look like a numbering mistake — it would look like a track disappearing.
  bool get titleCollides {
    final seen = <String>{};
    for (final s in steps) {
      if (!seen.add(normKey(s.official?.title ?? s.track.title))) return true;
    }
    return false;
  }

  bool get safe => !collides && !titleCollides && changing.isNotEmpty;
}

/// One file's part of a move, so the plan can be shown before anything is touched.
class MovePlan {
  final Track track;
  final String from;

  /// Where it would land, or null when the target album's folder can't be worked out — then the
  /// file stays put and only the grouping changes.
  final String? to;

  /// What happens to this file, in one word, so the dialog can say it rather than imply it.
  final MoveFate fate;
  const MovePlan(this.track, this.from, this.to, [this.fate = MoveFate.moves]);

  bool get movesFile => to != null && to != from;

  /// The filename, for a plan the user has to read a screenful of.
  String get name => File(from).uri.pathSegments.last;
}

/// Where the superseded copy of a colliding track is parked.
///
/// Not deleted — the user asked to tidy the folder, not to lose a file. Still scanned, and still
/// hidden from the tracklist by [LibraryStore._dedupeTracks], exactly as a duplicate is today.
const dupeFolder = '_dubbel';

/// What one track's file would do in a gather, and why.
enum MoveFate {
  /// Straight into the target folder under its own name.
  moves,

  /// The name is taken by a better copy, so this one is parked in [dupeFolder].
  toDupes,

  /// Already where it belongs, or there is nowhere to put it.
  stays,
}

/// Everything a merge would do on disk, so it can be read before anything is touched.
class MergePlan {
  /// The folder the record is being gathered into.
  final String? folder;
  final List<MovePlan> items;
  const MergePlan(this.folder, this.items);

  int get moving => items.where((i) => i.fate == MoveFate.moves).length;
  int get parking => items.where((i) => i.fate == MoveFate.toDupes).length;
  int get staying => items.where((i) => i.fate == MoveFate.stays).length;

  /// Nothing to do — every file is already in one folder.
  bool get isNoop => moving == 0 && parking == 0;

  /// "14 verhuizen · 3 naar _dubbel · 1 blijft staan"
  String get summary => [
        if (moving > 0) '$moving ${moving == 1 ? 'verhuist' : 'verhuizen'}',
        if (parking > 0) '$parking naar $dupeFolder',
        if (staying > 0) '$staying ${staying == 1 ? 'blijft' : 'blijven'} staan',
      ].join(' · ');
}

extension LibraryRenumber on LibraryStore {
  /// What taking [official] as this record's numbering would do. Nothing is written.
  ///
  /// Matched on TITLE and running time, never on the existing number — that number is the broken
  /// input. An album whose tags say 1, 1, 2, ?, 4, 6, 6, 7 … cannot be lined up positionally
  /// either, so the title is the only thing both sides can be trusted to agree on.
  RenumberPlan planRenumber(Album album, List<ChoiceTrack> official) {
    // A pool, so one official entry cannot claim two of our files: whichever matches it best takes
    // it and the other is reported as unmatched rather than silently duplicating a number.
    final pool = [...official];
    final steps = <RenumberStep>[];
    for (final t in album.tracks) {
      // The same matcher the album download uses — see matchOfficial in organize.dart. Two answers
      // to "is this the same song?" would be one too many.
      final best = matchOfficial(pool, t.title, t.duration?.inSeconds ?? 0);
      if (best == null) {
        steps.add(RenumberStep(t, null, null));
        continue;
      }
      pool.remove(best);
      steps.add(RenumberStep(t, best, trackNoFromPosition(best.position, best.disc, official)));
    }
    return RenumberPlan(steps, official.length);
  }

  /// Write a plan. The user's edit wins over the tags from here on, and outlives a rescan.
  Future<void> applyRenumber(RenumberPlan plan) async {
    for (final s in plan.steps) {
      if (s.newNo == null) continue;
      final c = _correctionsFor(s.track.path);
      c['trackNo'] = '${s.newNo}';
      c['trackTotal'] = '${plan.total}';
      final title = s.official?.title;
      if (title != null && title.trim().isNotEmpty) c['title'] = title.trim();
    }
    await saveCorrectionsNow();
    refreshFromCorrections();
  }
}

extension LibraryMove on LibraryStore {
  /// What moving [tracks] into [target] would do on disk. Nothing is touched.
  ///
  /// Shown before the move because this is the one operation here that rewrites the folder tree,
  /// and a wrong guess scatters a library rather than tidying it.
  /// What moving these tracks would do — the version a screen can await.
  ///
  /// On the machine with the files this is [planMove] with a Future round it. On a Mac or an iPad
  /// the PC works it out, because nothing here knows the folders, which copy is better, or that a
  /// name is already taken. Either way the dialog gets a real answer before anyone agrees to
  /// anything, which is what that dialog is for.
  Future<({String? folder, List<MovePlan> items})> planMoveAsync(
      List<Track> tracks, Album target) async {
    final client = _remote;
    if (client == null) {
      return (
        folder: target.tracks.isEmpty ? null : File(target.tracks.first.path).parent.path,
        items: planMove(tracks, target),
      );
    }
    final byId = {for (final t in tracks) _remoteTrackId(t.path): t};
    final res = await client.ask('/api/move/plan', {
      'albumId': remoteAlbumId(target),
      'trackIds': [for (final t in tracks) _remoteTrackId(t.path)],
    });
    final items = <MovePlan>[];
    for (final item in (res['items'] as List? ?? const [])) {
      if (item is! Map<String, dynamic>) continue;
      final track = byId[item['trackId'] as String?];
      if (track == null) continue;
      items.add(MovePlan(
        track,
        // The PC's real path, which is what the dialog should show — a stream URL would tell
        // nobody where the file is now.
        (item['from'] as String?) ?? track.path,
        item['to'] as String?,
        MoveFate.values.firstWhere((f) => f.name == item['fate'], orElse: () => MoveFate.moves),
      ));
    }
    return (folder: res['folder'] as String?, items: items);
  }

  List<MovePlan> planMove(List<Track> tracks, Album target) {
    final anchor = target.tracks.isEmpty ? null : File(target.tracks.first.path).parent.path;
    return anchor == null
        ? [for (final t in tracks) MovePlan(t, t.path, null, MoveFate.stays)]
        : _gather(tracks, anchor).items;
  }

  /// Every track of this RECORD, across editions — which is what a merge is about.
  ///
  /// An Album is one edition; the tile beside it is another. Planning from `album.tracks` alone
  /// would gather one half of a split record and leave the other exactly where it was.
  List<Track> recordTracks(Album album) {
    if (album.isSingle || album.tracks.isEmpty) return album.tracks;
    final t = album.tracks.first;
    return editionsOfRecord('album::${artistKey(t.artist)}|${normKey(t.album)}') ?? album.tracks;
  }

  /// Where the files of [album] would go if it were gathered into one folder. Nothing is touched.
  MergePlan planMerge(Album album) {
    final ts = recordTracks(album);
    final folder = _homeFolder(ts, album.title);
    if (folder == null) {
      return MergePlan(null, [for (final t in ts) MovePlan(t, t.path, null, MoveFate.stays)]);
    }
    return _gather(ts, folder);
  }

  /// The folder this record already mostly lives in.
  ///
  /// Whichever holds the most of its tracks: that is the least traffic, and for a record split by
  /// an edition it is the original rip rather than the one file Soulseek dropped somewhere else.
  /// A tie goes to the folder whose name reads most like the album's — so a merge lands in
  /// "Black & Blue" and not in whatever the downloader happened to call it.
  String? _homeFolder(List<Track> tracks, String title) {
    if (tracks.isEmpty) return null;
    final n = <String, int>{};
    for (final t in tracks) {
      n.update(File(t.path).parent.path, (v) => v + 1, ifAbsent: () => 1);
    }
    final want = normKey(title);
    final ranked = n.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        final an = normKey(a.key.split(Platform.pathSeparator).last);
        final bn = normKey(b.key.split(Platform.pathSeparator).last);
        final match = (bn == want ? 1 : 0) - (an == want ? 1 : 0);
        return match != 0 ? match : a.key.compareTo(b.key);
      });
    return ranked.first.key;
  }

  /// Work out, without touching anything, where each of [tracks] would land in [folder].
  MergePlan _gather(List<Track> tracks, String folder) {
    final sep = Platform.pathSeparator;
    // Names already spoken for in the target folder, and by which file. Seeded from the tracks that
    // are already there so two arrivals can't both claim one name.
    final taken = <String, String>{};
    for (final t in tracks) {
      final f = File(t.path);
      if (f.parent.path == folder) taken[f.uri.pathSegments.last.toLowerCase()] = t.path;
    }
    try {
      for (final e in Directory(folder).listSync(followLinks: false)) {
        if (e is File) taken.putIfAbsent(e.uri.pathSegments.last.toLowerCase(), () => e.path);
      }
    } catch (_) {/* folder unreadable — treat it as empty and let the move itself fail loudly */}

    final items = <MovePlan>[];
    // Tracks already dealt with because a better copy took their name. Without this a tenant bumped
    // before the loop reached it would be planned TWICE — once into _dubbel and once as staying —
    // and a plan that lists a file twice is a plan nobody can check.
    final bumped = <String>{};
    for (final t in tracks) {
      if (bumped.contains(t.path)) continue;
      final src = File(t.path);
      final name = src.uri.pathSegments.last;
      if (src.parent.path == folder) {
        items.add(MovePlan(t, t.path, null, MoveFate.stays));
        continue;
      }
      final holder = taken[name.toLowerCase()];
      if (holder == null) {
        taken[name.toLowerCase()] = t.path;
        items.add(MovePlan(t, t.path, '$folder$sep$name', MoveFate.moves));
        continue;
      }
      // The name is taken. Whichever copy is worse goes to the duplicates folder — same rule the
      // tracklist already uses to decide which of two copies you actually hear.
      // Only OUR tracks can be bumped; a stranger's file in the folder is left alone and we step aside.
      final tenant = tracks.where((x) => x.path == holder).firstOrNull;
      if (tenant != null && firstIsBetter(src, File(holder))) {
        final at = items.indexWhere((i) => i.track.path == holder);
        final aside = MovePlan(tenant, holder, '$folder$sep$dupeFolder$sep$name', MoveFate.toDupes);
        at >= 0 ? items[at] = aside : items.add(aside);
        bumped.add(holder);
        taken[name.toLowerCase()] = t.path;
        items.add(MovePlan(t, t.path, '$folder$sep$name', MoveFate.moves));
        continue;
      }
      items.add(MovePlan(t, t.path, '$folder$sep$dupeFolder$sep$name', MoveFate.toDupes));
    }
    return MergePlan(folder, items);
  }

  /// Carry out a plan. Returns, per source path, where that file actually ended up.
  ///
  /// Only files that really moved are in the map. Guessing afterwards from `File(to).exists()`
  /// would be wrong in the one case that matters: a destination that was already occupied is
  /// skipped, and the track's own file is then still at its old path — keying its correction to the
  /// stranger's path would leave the track ungrouped.
  ///
  /// Never overwrites. The correction naming this track's album is re-keyed to where the file
  /// landed — see [LibraryStore._reKeyCorrection] for what forgetting that used to cost.
  Future<Map<String, String>> _apply(List<MovePlan> plan) async {
    final landed = <String, String>{};
    for (final p in plan) {
      if (!p.movesFile) continue;
      try {
        final dest = File(p.to!);
        if (await dest.exists()) continue;
        await dest.parent.create(recursive: true);
        final at = await moveWithRetry(File(p.from), dest);
        _reKeyCorrection(p.from, at);
        landed[p.from] = at;
      } catch (_) {/* locked, or across volumes — the file stays put and stays in the library */}
    }
    return landed;
  }

  /// Move [tracks] into [target]: retag them into that album, and optionally carry the files along.
  ///
  /// The correction is what actually regroups them, so it is applied whether or not the file can
  /// be moved. A file that can't be moved — locked, or a name already taken — leaves the track
  /// grouped correctly and the file where it was, which is the safe half of the job.
  Future<int> moveTracksToAlbum(List<Track> tracks, Album target, AppSettings settings,
      {bool moveFiles = true, List<MovePlan>? plan}) async {
    if (isRemote) {
      final client = _remote!;
      final res = await client.ask('/api/move/apply', {
        'albumId': remoteAlbumId(target),
        'trackIds': [for (final t in tracks) _remoteTrackId(t.path)],
        'moveFiles': moveFiles,
        // The plan the user READ goes back with it. Letting the PC work it out again would let the
        // folder change between the screen they agreed to and the files that move.
        if (plan != null)
          'plan': [
            for (final p in plan)
              {'trackId': _remoteTrackId(p.track.path), 'to': p.to, 'fate': p.fate.name},
          ],
      });
      _catalogEtag = null;
      await loadRemote(quiet: true);
      return (res['moved'] as num?)?.toInt() ?? 0;
    }
    // The plan the user read, when there was one. Re-planning here would let the folder change
    // between the screen they approved and the files that move.
    final steps = plan ?? planMove(tracks, target);
    final landed = moveFiles ? await _apply(steps) : const <String, String>{};
    for (final p in steps) {
      final c = _correctionsFor(landed[p.from] ?? p.from);
      c['artist'] = cleanArtistName(target.artist);
      c['album'] = target.title;
    }
    await saveCorrectionsNow();
    await scan();
    return landed.length;
  }

  /// Gather every edition of [album] into one folder, carrying out [planMerge].
  ///
  /// The tags already say these are one record — that is why they show as one album — so nothing is
  /// retagged here. Only the files move.
  Future<int> gatherAlbumFiles(Album album, {List<MovePlan>? plan}) async {
    final landed = await _apply(plan ?? planMerge(album).items);
    if (landed.isNotEmpty) {
      await saveCorrectionsNow();
      await scan();
    }
    return landed.length;
  }
}

/// One track of a redundant album, matched to the copy already owned in the real album.
class DuplicatePair {
  /// The redundant copy.
  final Track dup;

  /// The copy already in the proper studio album that [dup] duplicates.
  final Track owned;

  /// True when [dup] is the better copy and should take [owned]'s place.
  final bool dupWins;
  const DuplicatePair(this.dup, this.owned, this.dupWins);
}

/// An album or single whose every track is already owned in a fuller studio album.
class RedundantAlbum {
  /// The junk single or fragment album.
  final Album source;

  /// The real album it all duplicates.
  final Album target;
  final List<DuplicatePair> pairs;
  const RedundantAlbum(this.source, this.target, this.pairs);

  /// How many of the redundant copies are actually better and will replace what's owned.
  int get upgrades => pairs.where((p) => p.dupWins).length;
}

/// The placeholder artist a file gets when its tags can't be read — see `_scanTags`.
final String _unknownArtistKey = artistKey('Onbekende artiest');

/// An album title that names a DISTINCT performance or version of a record, not the record itself.
///
/// A live "Gourmandises" is a different recording from the studio one, but the peer often tags the
/// track just "Gourmandises" with no marker — only the album name ("Alizée en concert") says it is
/// live. Folding it into the studio album on the strength of the title would quietly lose the live
/// take. A live album, like a greatest-hits, is a release the user keeps, so it is never a source
/// to clean away.
final RegExp _distinctPerformanceRe = RegExp(
    r'\b(live|concert|unplugged|acoustic|session|sessions|demo|demos|remix|remixes|'
    r'instrumental|karaoke|a ?cappella|acapella|orchestral|symphon)\b');

extension LibraryDuplicates on LibraryStore {
  /// Albums and singles that are entirely duplicates of a real album you already own.
  ///
  /// The two shapes this catches, both stale cruft from before downloads carried their album's
  /// identity: a fragment tagged like its own album ("Backstreet Boys (Special Edition)" holding
  /// only 9, 10, 13), and a junk single whose tags were unreadable so it filed itself under
  /// "Onbekende artiest" with the raw filename as its title.
  ///
  /// The safety is the ALL-of-it rule: a source is only redundant when EVERY one of its tracks is
  /// already in ONE proper studio album. A real greatest-hits spans several studio albums, so it
  /// can never be wholly contained in one and is never touched — which is what keeps a compilation
  /// you actually wanted from being swept away.
  List<RedundantAlbum> redundantAlbums() {
    // The real records a duplicate can fold back into: studio albums (not compilations, not
    // singles), with more than a token of tracks.
    final targets = [
      for (final a in albums)
        if (!a.isSingle &&
            a.tracks.length >= 2 &&
            classifyRelease(album: a.title, artist: a.artist) == RelKind.album)
          a
    ];
    if (targets.isEmpty) return const [];

    // Match one redundant track to a copy in [target]. Null when nothing in the target is it.
    //
    // A fragment carries real tags, so its TITLE is the strongest signal — stronger than the
    // filename, which the peer may have written as "09 - Every Time.flac". A junk single has no
    // usable title (its title IS the raw filename), so for that the filename against the target's
    // title is all there is, and fileOffersTitle reads the artist words in it correctly.
    Track? ownedIn(Album target, Track x, {required bool junk}) {
      final xDur = x.duration?.inSeconds ?? 0;
      if (!junk && normKey(x.title).isNotEmpty) {
        for (final y in target.tracks) {
          if (normKey(x.title) != normKey(y.title)) continue;
          final yDur = y.duration?.inSeconds ?? 0;
          // A different VERSION of the same song runs a different length; a couple of seconds is
          // just a different rip, so it is the same recording.
          if (xDur == 0 || yDur == 0 || (xDur - yDur).abs() <= 12) return y;
        }
      }
      for (final y in target.tracks) {
        if (fileOffersTitle(y.title, y.duration?.inSeconds, y.artist, x.path, xDur)) return y;
      }
      return null;
    }

    final out = <RedundantAlbum>[];
    for (final x in albums) {
      // Never fold away a release the user keeps on purpose: a real compilation, or a distinct
      // performance (a live album, a remix set, an unplugged session) whose tracks only look like
      // the studio ones because the marker sits in the album name, not the track title.
      if (!x.isSingle &&
          (classifyRelease(album: x.title, artist: x.artist) == RelKind.compilation ||
              _distinctPerformanceRe.hasMatch(normKey(x.title)))) {
        continue;
      }
      // A single whose artist never got read — the WAV filed under "Onbekende artiest". Its tags
      // are useless, so it is matched by filename against any album; anything with a real artist is
      // matched the cheap way, only against albums by that same artist.
      final junk = x.isSingle && (x.artist.trim().isEmpty || artistKey(x.artist) == _unknownArtistKey);

      Album? best;
      List<DuplicatePair>? bestPairs;
      for (final y in targets) {
        if (identical(x, y)) continue;
        // The target has to be at least as big — the fragment folds into the fuller record, never
        // the other way round. A single (one track) folds into any album that has it.
        if (y.tracks.length < x.tracks.length) continue;
        if (!junk && artistKey(x.artist) != artistKey(y.artist)) continue;

        final pairs = <DuplicatePair>[];
        var whole = true;
        for (final t in x.tracks) {
          final owned = ownedIn(y, t, junk: junk);
          if (owned == null) {
            whole = false;
            break;
          }
          pairs.add(DuplicatePair(t, owned, firstIsBetter(File(t.path), File(owned.path))));
        }
        if (!whole) continue;
        // Prefer the fullest target when several qualify, so a fragment lands in the real album.
        if (best == null || y.tracks.length > best.tracks.length) {
          best = y;
          bestPairs = pairs;
        }
      }
      if (best != null && bestPairs != null && bestPairs.isNotEmpty) {
        out.add(RedundantAlbum(x, best, bestPairs));
      }
    }
    return out;
  }

  /// Carry out a cleanup: keep the best copy of each track in [r.target], park the rest in _dubbel.
  ///
  /// The better copy wins even when it is the one in the fragment — here the Special Edition rips
  /// are the higher bitrate. A winning copy from the fragment moves into the target folder under
  /// its proper name and is retagged to the target's identity; the copy it beats goes to _dubbel.
  Future<void> consolidate(RedundantAlbum r) async {
    final sep = Platform.pathSeparator;
    final targetDir = r.target.tracks.isEmpty ? null : File(r.target.tracks.first.path).parent.path;
    if (targetDir == null) return;
    final dubbel = '$targetDir$sep$dupeFolder';

    Future<void> park(String from) async {
      try {
        final dest = File('$dubbel$sep${File(from).uri.pathSegments.last}');
        if (await dest.exists()) return; // already a copy there — leave this one where it is
        await dest.parent.create(recursive: true);
        final at = await moveWithRetry(File(from), dest);
        _reKeyCorrection(from, at);
      } catch (_) {/* locked or across volumes — the scan still sorts it out */}
    }

    for (final p in r.pairs) {
      if (!p.dupWins) {
        // The owned copy is as good or better — the duplicate simply goes away.
        await park(p.dup.path);
        continue;
      }
      // The duplicate is better: it takes the owned copy's slot. Park the owned copy first, then
      // move the winner onto its proper name and stamp it with the record's identity.
      await park(p.owned.path);
      final ext = () {
        final n = File(p.dup.path).uri.pathSegments.last;
        final i = n.lastIndexOf('.');
        return i < 0 ? '' : n.substring(i);
      }();
      final name = safeSeg('${p.owned.trackNo.toString().padLeft(2, '0')} - ${p.owned.title}$ext');
      final to = '$targetDir$sep$name';
      try {
        if (!await File(to).exists()) {
          final at = await moveWithRetry(File(p.dup.path), File(to));
          _reKeyCorrection(p.dup.path, at);
          await stampTags(
              File(at),
              TrackTags(
                title: p.owned.title,
                artist: r.target.artist,
                album: r.target.title,
                albumArtist: r.target.artist,
                trackNo: p.owned.trackNo,
                trackTotal: r.target.tracks.length,
                year: p.owned.year ?? r.target.year,
              ));
        }
      } catch (_) {/* couldn't move — leave both; the next scan still shows one via dedup */}
    }

    await saveCorrectionsNow();
    // The source folder is empty now (a single's parent may hold others — only remove if bare).
    final srcDir = r.source.tracks.isEmpty ? null : File(r.source.tracks.first.path).parent.path;
    if (srcDir != null && srcDir != targetDir) {
      try {
        final d = Directory(srcDir);
        if (d.existsSync() && d.listSync().isEmpty) d.deleteSync();
      } catch (_) {}
    }
    await scan();
  }
}
