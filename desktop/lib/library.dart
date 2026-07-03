import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'enrichment.dart';
import 'models.dart';
import 'settings.dart';

/// Scans a music folder, reads tags + embedded covers, and groups into albums.
class LibraryStore extends ChangeNotifier {
  final List<Track> tracks = [];
  List<Album> albums = [];
  bool scanning = false;
  int scanned = 0;
  String rootPath = r'D:\Flac music 2024';

  static const _audioExt = {
    '.flac', '.mp3', '.m4a', '.wav', '.ogg', '.opus', '.aac', '.wma', '.alac'
  };

  Future<void> scan() async {
    scanning = true;
    scanned = 0;
    tracks.clear();
    albums = [];
    notifyListeners();

    final dir = Directory(rootPath);
    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && _audioExt.contains(_ext(entity.path))) {
          final t = _read(entity);
          if (t != null) {
            tracks.add(t);
            scanned++;
            if (scanned % 15 == 0) notifyListeners();
          }
        }
      }
    }
    _buildAlbums();
    scanning = false;
    notifyListeners();
  }

  Track? _read(File file) {
    try {
      final meta = readMetadata(file, getImage: true);
      final cover = meta.pictures.isNotEmpty ? meta.pictures.first.bytes : null;
      final title = (meta.title != null && meta.title!.trim().isNotEmpty)
          ? meta.title!.trim()
          : _baseName(file.path);
      return Track(
        path: file.path,
        title: title,
        artist: (meta.artist?.trim().isNotEmpty ?? false) ? meta.artist!.trim() : 'Onbekende artiest',
        album: (meta.album?.trim().isNotEmpty ?? false) ? meta.album!.trim() : _parentName(file.path),
        trackNo: meta.trackNumber ?? 0,
        cover: cover,
        duration: meta.duration,
        isFlac: _ext(file.path) == '.flac',
      );
    } catch (_) {
      return null;
    }
  }

  void _buildAlbums() {
    final map = <String, List<Track>>{};
    for (final t in tracks) {
      map.putIfAbsent('${t.artist.toLowerCase()}|${t.album.toLowerCase()}', () => []).add(t);
    }
    albums = map.values.map((ts) {
      ts.sort((a, b) => a.trackNo.compareTo(b.trackNo));
      return Album(ts.first.album, ts.first.artist, ts);
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  bool enriching = false;

  /// Fill missing album covers from the web (Deezer/Discogs/MusicBrainz), cached on disk.
  Future<void> enrich(AppSettings settings) async {
    enriching = true;
    final enricher = CoverEnricher(settings);
    for (final album in albums) {
      if (album.embedded != null) continue;
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

  List<String> get artists {
    final set = <String>{};
    for (final a in albums) {
      set.add(a.artist);
    }
    final list = set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  String _ext(String p) {
    final i = p.lastIndexOf('.');
    return i < 0 ? '' : p.substring(i).toLowerCase();
  }

  String _baseName(String p) {
    final s = p.replaceAll('\\', '/').split('/').last;
    final i = s.lastIndexOf('.');
    return i < 0 ? s : s.substring(0, i);
  }

  String _parentName(String p) {
    final parts = p.replaceAll('\\', '/').split('/');
    return parts.length >= 2 ? parts[parts.length - 2] : 'Onbekend album';
  }
}
