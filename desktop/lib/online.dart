import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'search.dart';
import 'settings.dart';
import 'soulseek.dart';
import 'torbox.dart';

/// TorBox search + resolve + download, ported from the server's OnlineService.
class OnlineService {
  final AppSettings settings;
  final TorBox torbox;
  final SearchAggregator aggregator;
  OnlineService(this.settings)
      : torbox = TorBox(() => settings.torboxToken),
        aggregator = SearchAggregator([ApibaySource(), BitSearchSource(), KnabenSource()]);

  bool get torboxReady => torbox.hasKey;

  Future<List<SearchResult>> search(String query) async {
    final results = await aggregator.search(query);
    if (!torbox.hasKey) return results;
    // Mark instantly-cached results (top 40, batches of 20).
    final top = results.take(40).map((r) => r.hash.toLowerCase()).toList();
    final cached = <String>{};
    for (var i = 0; i < top.length; i += 20) {
      cached.addAll(await torbox.checkCached(top.sublist(i, (i + 20).clamp(0, top.length))));
    }
    for (final r in results) {
      r.cached = cached.contains(r.hash.toLowerCase());
    }
    results.sort((a, b) {
      if (a.cached != b.cached) return a.cached ? -1 : 1;
      return b.seeders.compareTo(a.seeders);
    });
    return results;
  }

  Future<(int?, String)> _addOrFind(SearchResult r) async {
    final (success, id, hash0, detail) = await torbox.addMagnet(r.magnet);
    final hash = (hash0 != null && hash0.isNotEmpty) ? hash0 : r.hash;
    if (hash.isEmpty) throw 'Torrent heeft geen infohash';
    if (success) return (id, hash);
    if (detail.toLowerCase().contains('already')) {
      final item = (await torbox.listTorrents())
          .cast<TbTorrent?>()
          .firstWhere((t) => t?.hash?.toLowerCase() == hash.toLowerCase(), orElse: () => null);
      return (item?.id, hash);
    }
    throw detail.isNotEmpty ? detail : 'Kon torrent niet toevoegen';
  }

  Future<TbTorrent> _pollReady(int? id, String hash, {bool patient = false}) async {
    var delayMs = 2000;
    var noProgress = 0;
    var readyNoAudio = 0;
    final maxAttempts = patient ? 45 : 30;
    final stallTimeout = patient ? 45000 : 25000;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final list = await torbox.listTorrents();
      final item = list.cast<TbTorrent?>().firstWhere(
          (t) => (id != null && t?.id == id) || (t?.hash?.toLowerCase() == hash.toLowerCase()),
          orElse: () => null);
      if (item == null) {
        noProgress += delayMs;
      } else if (item.isFailed) {
        throw 'Bron mislukt: ${item.status}';
      } else if (item.isReady && item.audio.isNotEmpty) {
        return item;
      } else if (item.isReady) {
        readyNoAudio += delayMs;
        if (readyNoAudio >= 18000) throw 'Geen afspeelbare audio in deze bron';
      } else {
        if (item.progress <= 0) {
          noProgress += delayMs;
        } else {
          noProgress = 0;
        }
      }
      if (noProgress >= stallTimeout) throw 'Bron loopt vast — geen voortgang';
      await Future.delayed(Duration(milliseconds: delayMs));
      if (attempt >= 1) delayMs = (delayMs * 1.5).round().clamp(0, 10000);
    }
    throw 'Time-out bij voorbereiden van deze bron';
  }

  TbFile? _bestAudio(TbTorrent t) {
    final audio = t.audio;
    if (audio.isEmpty) return null;
    audio.sort((a, b) {
      final fa = a.isFlac ? 1 : 0, fb = b.isFlac ? 1 : 0;
      if (fa != fb) return fb - fa;
      return b.size.compareTo(a.size);
    });
    return audio.first;
  }

  List<TbFile> _sortedAudio(TbTorrent t) {
    final audio = t.audio;
    audio.sort((a, b) {
      final fa = a.isFlac ? 1 : 0, fb = b.isFlac ? 1 : 0;
      if (fa != fb) return fb - fa;
      return a.name.compareTo(b.name);
    });
    return audio;
  }

  /// Resolve the single best track of a result to a playable URL.
  Future<String> resolveStreamUrl(SearchResult r) async {
    if (!torbox.hasKey) throw 'Stel eerst je TorBox-sleutel in (Instellingen).';
    final (id, hash) = await _addOrFind(r);
    final item = await _pollReady(id, hash, patient: !r.cached);
    final best = _bestAudio(item);
    if (best == null) throw 'Geen audio in deze torrent';
    final url = await torbox.requestDownload(item.id, best.id);
    if (url == null) throw 'Lege download-URL';
    return url;
  }

  /// (torrent, audio files) for the track picker.
  Future<(TbTorrent, List<TbFile>)> tracklist(SearchResult r) async {
    if (!torbox.hasKey) throw 'Stel eerst je TorBox-sleutel in (Instellingen).';
    final (id, hash) = await _addOrFind(r);
    final item = await _pollReady(id, hash);
    final files = _sortedAudio(item);
    if (files.isEmpty) throw 'Geen audio in deze torrent';
    return (item, files);
  }

  Future<String> resolveTrackUrl(int torrentId, int fileId) async {
    final url = await torbox.requestDownload(torrentId, fileId);
    if (url == null) throw 'Lege download-URL';
    return url;
  }

  /// Resolve the torrent + the files to download (all audio, or one file).
  Future<(TbTorrent, List<TbFile>)> resolveForDownload(SearchResult r, int? fileId) async {
    if (!torbox.hasKey) throw 'Stel eerst je TorBox-sleutel in (Instellingen).';
    final (id, hash) = await _addOrFind(r);
    final item = await _pollReady(id, hash, patient: !r.cached);
    final files = fileId != null ? item.files.where((f) => f.id == fileId).toList() : _sortedAudio(item);
    if (files.isEmpty) throw 'Geen audio gevonden';
    return (item, files);
  }
}

/// Soulseek search (with the first-character "*" quirk) + credentials gate.
class SoulseekService {
  final AppSettings settings;
  final SoulseekClient client = SoulseekClient();
  SoulseekService(this.settings);

  bool get available => settings.soulseekUser.isNotEmpty && settings.soulseekPass.isNotEmpty;

  Future<List<SoulseekFile>> search(String query) async {
    if (!available) return [];
    final q = query.trim();
    // Soulseek quirk: the first character is often dropped — also try a "*"-prefixed variant.
    final variants = <String>{q};
    if (q.length > 2) variants.add('*${q.substring(1)}');
    final all = <SoulseekFile>[];
    for (final v in variants) {
      try {
        all.addAll(await client.search(settings.soulseekUser, settings.soulseekPass, v));
      } catch (_) {}
    }
    final seen = <String>{};
    return all.where((f) => seen.add('${f.username}|${f.filename}')).toList();
  }
}

class DownloadJob {
  final String name;
  double progress;
  String status; // downloading | done | failed
  DownloadJob(this.name) : progress = 0, status = 'downloading';
}

/// Streams TorBox + Soulseek downloads into the music library (with progress), then rescans.
class DownloadManager extends ChangeNotifier {
  final OnlineService online;
  final SoulseekService soulseek;
  final String musicRoot;
  final Future<void> Function() onLibraryChanged;
  DownloadManager(this.online, this.soulseek, this.musicRoot, this.onLibraryChanged);

  final List<DownloadJob> jobs = [];

  Future<void> enqueueSoulseek(SoulseekFile file) async {
    if (!soulseek.available) throw 'Stel je Soulseek-login in (Instellingen).';
    final dir = Directory('$musicRoot${Platform.pathSeparator}DebridMusic Downloads${Platform.pathSeparator}Soulseek');
    await dir.create(recursive: true);
    final dest = File('${dir.path}${Platform.pathSeparator}${_sanitize(file.displayName)}');
    final job = DownloadJob(file.displayName);
    jobs.insert(0, job);
    notifyListeners();
    unawaited(() async {
      final res = await soulseek.client.download(
        soulseek.settings.soulseekUser, soulseek.settings.soulseekPass, file, dest, (rec, tot) {
        if (tot > 0) {
          final p = (rec / tot).clamp(0.0, 1.0);
          if (p - job.progress > 0.02) {
            job.progress = p;
            notifyListeners();
          }
        }
      });
      if (res is SlskDone) {
        job.progress = 1;
        job.status = 'done';
        notifyListeners();
        await onLibraryChanged();
      } else {
        job.status = 'failed';
        notifyListeners();
      }
    }());
  }

  Future<int> enqueue(SearchResult result, {int? fileId}) async {
    final (torrent, files) = await online.resolveForDownload(result, fileId);
    final destDir = Directory('$musicRoot${Platform.pathSeparator}DebridMusic Downloads${Platform.pathSeparator}${_sanitize(torrent.name)}');
    await destDir.create(recursive: true);
    for (final f in files) {
      final job = DownloadJob(f.label);
      jobs.insert(0, job);
      notifyListeners();
      // Sequential per-file within this call; UI can queue more.
      unawaited(_download(torrent.id, f, destDir, job));
    }
    return files.length;
  }

  Future<void> _download(int torrentId, TbFile f, Directory destDir, DownloadJob job) async {
    try {
      final url = await online.resolveTrackUrl(torrentId, f.id);
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(url));
      final resp = await client.send(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) throw 'HTTP ${resp.statusCode}';
      final total = resp.contentLength ?? f.size;
      final dest = File('${destDir.path}${Platform.pathSeparator}${_sanitize(f.label)}');
      final sink = dest.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final p = (received / total).clamp(0.0, 1.0);
          if (p - job.progress > 0.02) {
            job.progress = p;
            notifyListeners();
          }
        }
      }
      await sink.close();
      client.close();
      job.progress = 1;
      job.status = 'done';
      notifyListeners();
      await onLibraryChanged();
    } catch (_) {
      job.status = 'failed';
      notifyListeners();
    }
  }

  String _sanitize(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
}
