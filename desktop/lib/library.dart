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
  final Map<String, Uint8List> artistImages = {};
  String rootPath = r'D:\Flac music 2024';

  Future<void> scan() async {
    scanning = true;
    scanned = 0;
    tracks.clear();
    albums = [];
    notifyListeners();

    // Pass 1 — tags, off the UI thread.
    final raw = await Isolate.run(() => _scanTags(rootPath));
    tracks.addAll(raw.map(_trackFromMap));
    scanned = tracks.length;
    _buildAlbums();
    scanning = false;
    notifyListeners();

    // Pass 2 — one cover per album, off the UI thread.
    final firstPaths = albums.map((a) => a.tracks.first.path).toList();
    final covers = await Isolate.run(() => _readCovers(firstPaths));
    for (final a in albums) {
      a.embeddedCover = covers[a.tracks.first.path];
    }
    notifyListeners();
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
  }

  /// Fill missing album covers from the web (Deezer/Discogs/MusicBrainz), cached on disk.
  Future<void> enrich(AppSettings settings) async {
    enriching = true;
    final enricher = CoverEnricher(settings);
    for (final album in albums) {
      if (album.embeddedCover != null) continue;
      Uint8List? bytes = await enricher.cached(album);
      bytes ??= await enricher.fetchAndCache(album);
      if (bytes != null) {
        album.enriched = bytes;
        notifyListeners();
      }
    }
    enriching = false;
    notifyListeners();
  }

  /// Fetch artist photos (Deezer), cached on disk.
  Future<void> enrichArtists(AppSettings settings) async {
    final enricher = CoverEnricher(settings);
    for (final name in artists) {
      if (artistImages.containsKey(name)) continue;
      Uint8List? bytes = await enricher.cachedArtist(name);
      bytes ??= await enricher.fetchArtistImage(name);
      if (bytes != null) {
        artistImages[name] = bytes;
        notifyListeners();
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
