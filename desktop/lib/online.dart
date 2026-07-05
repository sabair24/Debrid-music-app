import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'rutracker.dart';
import 'search.dart';
import 'settings.dart';
import 'soulseek.dart';
import 'torbox.dart';

/// TorBox search + resolve + download, ported from the server's OnlineService.
class OnlineService {
  final AppSettings settings;
  final TorBox torbox;
  final RuTrackerService rutracker;
  final SearchAggregator aggregator;
  OnlineService(this.settings)
      : torbox = TorBox(() => settings.torboxToken),
        rutracker = RuTrackerService(settings),
        aggregator = SearchAggregator([
          ApibaySource(),
          BitSearchSource(),
          KnabenSource(),
          RuTrackerSource(RuTrackerService(settings)),
        ]);

  bool get torboxReady => torbox.hasKey;

  Future<List<SearchResult>> search(String query, {void Function(List<SearchResult>)? onPartial}) async {
    // Stream raw hits as each source finishes (fast perceived results); the ⚡Instant
    // cache marks are applied on the final pass below.
    final results = await aggregator.search(query, onPartial: onPartial);
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

  Future<TbTorrent> _pollReady(int? id, String hash,
      {bool patient = false, void Function(double progress, String status)? onProgress}) async {
    var delayMs = 2000;
    var noProgress = 0;
    var readyNoAudio = 0;
    // Big, low-seed torrents (a whole discography) take TorBox a long time to fetch from
    // few peers — be patient and, crucially, report progress so it's not a mystery spinner.
    final maxAttempts = patient ? 120 : 30;
    final stallTimeout = patient ? 90000 : 25000;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final list = await torbox.listTorrents();
      final item = list.cast<TbTorrent?>().firstWhere(
          (t) => (id != null && t?.id == id) || (t?.hash?.toLowerCase() == hash.toLowerCase()),
          orElse: () => null);
      onProgress?.call(item?.progress ?? 0, item?.status ?? 'toevoegen');
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

  /// Resolve a recommended track (artist + title) to a playable URL, picking the file
  /// that actually matches [title] (so an album torrent doesn't play the wrong song).
  /// [instantOnly] true (Radio) = cached TorBox sources only, for speed; false (an
  /// explicit play) also tries un-cached sources (slower). Returns null if nothing matches.
  Future<String?> resolveRadio(String artist, String title, {bool instantOnly = true}) async {
    if (!torbox.hasKey) return null;
    final results = await search('$artist $title');
    if (results.isEmpty) return null;
    int score(SearchResult r) {
      final n = r.name.toLowerCase();
      var s = 0;
      if (_titleMatch(r.name, title)) s += 60;
      if (RegExp('flac', caseSensitive: false).hasMatch(n)) s += 10;
      if (r.size < 120 * 1000 * 1000) s += 20; // small => likely a single track, not an album
      return s + (r.seeders > 0 ? 3 : 0);
    }

    final top = (results.toList()..sort((a, b) => score(b) - score(a))).take(10).toList();
    // Directly cache-check these candidates — search() only flags the top 40 overall.
    Set<String> cachedSet = {};
    try {
      cachedSet = await torbox.checkCached(top.map((r) => r.hash.toLowerCase()).toList());
    } catch (_) {}
    bool isCached(SearchResult r) => r.cached || cachedSet.contains(r.hash.toLowerCase());
    final cached = top.where(isCached).toList();
    // Cached first; for an explicit play, fall back to un-cached (slower) sources too.
    final candidates = instantOnly ? cached : [...cached, ...top.where((r) => !isCached(r))];
    for (final r in candidates.take(instantOnly ? 3 : 4)) {
      try {
        final (item, files) = await resolveForDownload(r, null); // patient poll when not cached
        TbFile? pick;
        for (final f in files) {
          if (_titleMatch(f.name, title)) {
            pick = f;
            break;
          }
        }
        pick ??= files.length == 1 ? files.first : null; // single-track torrent
        if (pick == null) continue; // multi-track, no title match => avoid the wrong song
        final url = await torbox.requestDownload(item.id, pick.id);
        if (url != null) return url;
      } catch (_) {}
    }
    return null;
  }

  bool _titleMatch(String name, String title) {
    String n(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final t = n(title);
    return t.length >= 3 && n(name).contains(t);
  }

  /// (torrent, audio files) for the track picker.
  Future<(TbTorrent, List<TbFile>)> tracklist(SearchResult r,
      {void Function(double, String)? onProgress}) async {
    if (!torbox.hasKey) throw 'Stel eerst je TorBox-sleutel in (Instellingen).';
    final (id, hash) = await _addOrFind(r);
    final item = await _pollReady(id, hash, patient: !r.cached, onProgress: onProgress);
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
  Future<(TbTorrent, List<TbFile>)> resolveForDownload(SearchResult r, int? fileId,
      {void Function(double, String)? onProgress}) async {
    if (!torbox.hasKey) throw 'Stel eerst je TorBox-sleutel in (Instellingen).';
    final (id, hash) = await _addOrFind(r);
    final item = await _pollReady(id, hash, patient: !r.cached, onProgress: onProgress);
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

  /// Confirm the Soulseek login works (used by the connection-status check).
  Future<bool> verify() async {
    if (!available) return false;
    return client.verifyLogin(settings.soulseekUser, settings.soulseekPass);
  }

  /// [onPartial] streams merged results as they arrive (both variants run in parallel).
  Future<List<SoulseekFile>> search(String query, {void Function(List<SoulseekFile>)? onPartial}) async {
    if (!available) return [];
    final q = query.trim();
    // Soulseek quirk: the first character is often dropped — also try a "*"-prefixed variant.
    final variants = <String>{q};
    if (q.length > 2) variants.add('*${q.substring(1)}');
    final merged = <String, SoulseekFile>{}; // username|filename → file
    void mergeEmit(List<SoulseekFile> partial) {
      for (final f in partial) {
        merged['${f.username}|${f.filename}'] = f;
      }
      if (onPartial != null) onPartial(sortSoulseek(merged.values));
    }

    // Run both variants concurrently (was sequential = up to 2× the wait). Each variant
    // streams straight into `merged` via mergeEmit — no need to re-merge the return value.
    await Future.wait(variants.map((v) async {
      try {
        await client.search(settings.soulseekUser, settings.soulseekPass, v, onPartial: mergeEmit);
      } catch (_) {}
    }));
    return sortSoulseek(merged.values);
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

  /// Add a torrent download. Non-blocking: a "preparing" job shows TorBox's fetch progress
  /// immediately (so a big/low-seed torrent isn't a mystery spinner), then per-file jobs
  /// start once TorBox has it ready.
  void enqueue(SearchResult result, {int? fileId}) {
    final prep = DownloadJob(fileId != null ? result.name : 'Voorbereiden: ${result.name}')..status = 'preparing';
    jobs.insert(0, prep);
    notifyListeners();
    unawaited(() async {
      try {
        final (torrent, files) = await online.resolveForDownload(result, fileId, onProgress: (p, s) {
          prep.progress = p;
          notifyListeners();
        });
        jobs.remove(prep);
        final destDir = Directory(
            '$musicRoot${Platform.pathSeparator}DebridMusic Downloads${Platform.pathSeparator}${_sanitize(torrent.name)}');
        await destDir.create(recursive: true);
        for (final f in files) {
          final job = DownloadJob(f.label);
          jobs.insert(0, job);
          notifyListeners();
          unawaited(_download(torrent.id, f, destDir, job));
        }
        notifyListeners();
      } catch (e) {
        prep.status = 'failed';
        notifyListeners();
      }
    }());
  }

  /// Download every file in a list (used by "Download album" from Soulseek).
  Future<int> enqueueSoulseekAll(List<SoulseekFile> files) async {
    var n = 0;
    for (final f in files) {
      try {
        await enqueueSoulseek(f);
        n++;
      } catch (_) {}
    }
    return n;
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
