/// Music kept on this device, for when the PC is not there.
///
/// A copy, not a second library. The PC still owns the files, the tags and the grouping — this
/// holds bytes and an index of which library path they belong to, so that everything upstream keeps
/// working from the catalogue the PC serves. Nothing here decides what an album IS.
///
/// The whole point sits in one place: [localFor]. Playback in this app goes through exactly one
/// choke point, [PlayerStore.mediaResolver], so "play the copy if we have it, otherwise stream"
/// is a single decision rather than a branch in every screen.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'paths.dart';

/// One track that lives on this device.
class OfflineTrack {
  const OfflineTrack({
    required this.path,
    required this.file,
    required this.bytes,
    required this.title,
    required this.artist,
    required this.album,
    required this.savedAt,
  });

  /// The library path, exactly as the PC's catalogue gives it. The key to everything: it is what
  /// [Track.path] holds, so a lookup needs no matching on titles.
  final String path;

  /// Where the bytes are on this device.
  final String file;

  final int bytes;
  final String title;
  final String artist;
  final String album;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'path': path,
        'file': file,
        'bytes': bytes,
        'title': title,
        'artist': artist,
        'album': album,
        'savedAt': savedAt.toUtc().toIso8601String(),
      };

  static OfflineTrack? fromJson(Map<String, dynamic> j) {
    final path = (j['path'] ?? '').toString();
    final file = (j['file'] ?? '').toString();
    if (path.isEmpty || file.isEmpty) return null;
    return OfflineTrack(
      path: path,
      file: file,
      bytes: (j['bytes'] as num?)?.toInt() ?? 0,
      title: (j['title'] ?? '').toString(),
      artist: (j['artist'] ?? '').toString(),
      album: (j['album'] ?? '').toString(),
      savedAt: DateTime.tryParse((j['savedAt'] ?? '').toString()) ?? DateTime(1970),
    );
  }
}

/// A download in flight, so a screen can show it moving.
class OfflineJob {
  OfflineJob(this.path, this.title);
  final String path;
  final String title;

  /// 0..1, or null while the server has not said how big the file is.
  double? progress;
  String? error;
  bool done = false;

  /// Staat dit nummer nog in de rij, of loopt het al?
  ///
  /// Het verschil hoort op het scherm: een wieltje dat draait voor iets wat nog niet begonnen is
  /// leest als een download die vastzit.
  bool wacht = false;
}

/// Eén nummer dat opgehaald moet worden, met alles wat [OfflineStore.download] ervoor nodig heeft.
///
/// Bestaat omdat een album als GEHEEL wordt gevraagd. Zonder zoiets moest de aanvrager de nummers
/// zelf één voor één afwachten, en dat is precies waar het misging: die lus stond in de knop op de
/// albumpagina en stopte zodra je die pagina verliet.
class OfflineRequest {
  const OfflineRequest({
    required this.libraryPath,
    required this.url,
    required this.title,
    required this.artist,
    required this.album,
  });

  final String libraryPath;
  final String url;
  final String title;
  final String artist;
  final String album;
}

/// What this device is holding, and what is on its way.
class OfflineStore extends ChangeNotifier {
  OfflineStore({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  final Map<String, OfflineTrack> _tracks = {};
  final Map<String, OfflineJob> _jobs = {};

  /// Cancelled by [remove] and by [clear], so a download that is deleted mid-flight stops writing.
  final Set<String> _cancelled = {};

  bool _loaded = false;

  List<OfflineTrack> get tracks {
    final all = _tracks.values.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return all;
  }

  List<OfflineJob> get jobs => _jobs.values.toList();

  int get bytes => _tracks.values.fold(0, (sum, t) => sum + t.bytes);

  bool has(String path) => _tracks.containsKey(path);
  bool isBusy(String path) => _jobs.containsKey(path);

  /// Nummers die nog opgehaald moeten worden, in de volgorde waarin ze gevraagd zijn.
  ///
  /// **Waarom deze rij hier staat en niet in de knop.** Een album werd opgehaald door een lus in
  /// `_OfflineAlbumButtonState`, met `if (!mounted) return;` per nummer. Verliet je de albumpagina,
  /// dan viel die lus stil: gemeten op 17-08-2026 met Discovery (14 nummers) — tikken, vier
  /// seconden later terug naar de lijst, en er stonden er 3 op het toestel. Geen melding, geen
  /// mislukte download, niets in de lijst. Later in de auto zijn dat elf nummers die er niet zijn.
  ///
  /// Een winkel leeft langer dan een scherm, dus hier hoort het thuis.
  final List<OfflineRequest> _wachtrij = [];
  bool _pompt = false;

  /// Hoeveel er nog te gaan zijn, voor een scherm dat dat wil zeggen.
  int get wachtend => _wachtrij.length;

  /// Zet deze nummers op het toestel. Keert meteen terug; het ophalen loopt door.
  ///
  /// Eén tegelijk, net als voorheen: een telefoonradio wordt er niet sneller van om vijf bestanden
  /// van honderd megabyte door elkaar te trekken, en zo blijft de volgorde die van de plaat.
  void bewaarAlles(Iterable<OfflineRequest> items) {
    var toegevoegd = 0;
    for (final r in items) {
      if (_tracks.containsKey(r.libraryPath)) continue;
      if (_jobs.containsKey(r.libraryPath)) continue;
      _jobs[r.libraryPath] = OfflineJob(r.libraryPath, r.title)..wacht = true;
      _wachtrij.add(r);
      toegevoegd++;
    }
    if (toegevoegd == 0) return;
    notifyListeners();
    unawaited(_pomp());
  }

  Future<void> _pomp() async {
    if (_pompt) return;
    _pompt = true;
    try {
      while (_wachtrij.isNotEmpty) {
        final r = _wachtrij.removeAt(0);
        // Nooit gooien: één nummer dat niet lukt mag de rest van de plaat niet meenemen.
        await download(
          libraryPath: r.libraryPath,
          url: r.url,
          title: r.title,
          artist: r.artist,
          album: r.album,
        );
      }
    } finally {
      _pompt = false;
    }
  }

  /// The file on this device for a library path, or null.
  ///
  /// Checks the disk rather than trusting the index: a copy can be gone — Android reclaims an
  /// app's files under storage pressure without telling anybody — and handing libmpv a path to
  /// nothing produces a track that simply refuses to play, with no way to tell why.
  String? localFor(String libraryPath) {
    final t = _tracks[libraryPath];
    if (t == null) return null;
    if (!File(t.file).existsSync()) {
      _tracks.remove(libraryPath);
      unawaited(_save());
      return null;
    }
    return t.file;
  }

  Directory get _dir => appSubdir('offline');
  File get _index => appFile('offline.json');

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = _index;
      if (!await f.exists()) return;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! List) return;
      for (final e in decoded) {
        if (e is! Map<String, dynamic>) continue;
        final t = OfflineTrack.fromJson(e);
        if (t != null) _tracks[t.path] = t;
      }
      notifyListeners();
    } catch (e) {
      // An unreadable index is an empty one. The bytes are still there and will simply be fetched
      // again; losing the index must never lose the ability to play from the PC.
      debugPrint('Offline index unreadable: $e');
    }
  }

  Future<void> _save() async {
    try {
      await _index.writeAsString(jsonEncode([for (final t in _tracks.values) t.toJson()]));
    } catch (e) {
      debugPrint('Offline index not saved: $e');
    }
  }

  /// Where a track's bytes go.
  ///
  /// Named from a hash of the library path, not from the title. Titles carry slashes, colons and
  /// characters Android's filesystem refuses, and two pressings of one album share a title — the
  /// path is already unique and the index knows what it means.
  File _fileFor(String libraryPath, String extension) {
    final digest = sha1.convert(utf8.encode(libraryPath)).toString().substring(0, 16);
    final ext = extension.isEmpty ? 'bin' : extension;
    return File('${_dir.path}${Platform.pathSeparator}$digest.$ext');
  }

  /// Fetch one track onto this device.
  ///
  /// [url] is the authorised stream URL — this class deliberately knows nothing about tokens or
  /// which PC is which; the caller already has a [RemoteClient] that does.
  Future<bool> download({
    required String libraryPath,
    required String url,
    required String title,
    required String artist,
    required String album,
  }) async {
    if (_tracks.containsKey(libraryPath)) return true;

    // Een taak die al WACHT is er eentje uit [_wachtrij] en wordt hier overgenomen; een taak die al
    // LOOPT is een tweede klik op hetzelfde nummer en hoort niets te doen.
    final bestaand = _jobs[libraryPath];
    if (bestaand != null && !bestaand.wacht) return true;

    final job = bestaand ?? OfflineJob(libraryPath, title);
    job.wacht = false;
    _jobs[libraryPath] = job;
    _cancelled.remove(libraryPath);
    notifyListeners();

    // The extension is what tells a player the format — libmpv and AVFoundation both sniff it
    // before reading a byte — so it is taken from the library path rather than invented.
    final dot = libraryPath.lastIndexOf('.');
    final ext = dot > 0 && dot > libraryPath.length - 6 ? libraryPath.substring(dot + 1) : 'flac';
    final target = _fileFor(libraryPath, ext);
    final temp = File('${target.path}.part');

    // Held outside the try so the failure path can close it. A connection that drops mid-stream
    // makes `res.stream` throw, which skips the close below — and Windows refuses to delete a file
    // that is still open, so the .part survived and the next attempt found a name it thought it
    // already had. On a Mac the same code passes: unlink does not mind an open handle.
    IOSink? sink;
    try {
      final res = await _http.send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');

      final total = res.contentLength ?? 0;
      var written = 0;
      // Two names for one sink on purpose: `out` is what writes, `sink` is only "there is still a
      // handle to let go of". Nulling `sink` after a clean close is what keeps the failure path
      // below from closing an already-closed sink.
      final out = temp.openWrite();
      sink = out;
      await for (final chunk in res.stream) {
        if (_cancelled.contains(libraryPath)) {
          await out.close();
          sink = null;
          await temp.delete();
          _jobs.remove(libraryPath);
          notifyListeners();
          return false;
        }
        out.add(chunk);
        written += chunk.length;
        if (total > 0) {
          final next = written / total;
          // Only when the bar would visibly move. A FLAC is tens of thousands of chunks and a
          // notifyListeners per chunk rebuilds the whole downloads screen thousands of times.
          if (job.progress == null || next - job.progress! >= 0.02) {
            job.progress = next;
            notifyListeners();
          }
        }
      }
      await out.close();
      sink = null; // closed cleanly — nothing for the failure path below to close again

      // The server said how big it would be. Fewer bytes than that means the connection dropped,
      // and a truncated FLAC is worse than no copy at all: it plays and then stops, which sounds
      // like the track is broken rather than like a download that failed.
      if (total > 0 && written < total) {
        throw HttpException('afgebroken: $written van $total bytes');
      }

      // Into place only once it is whole. A half file that a crash left behind would otherwise be
      // indistinguishable from a finished one and would play as a track that stops halfway.
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);

      _tracks[libraryPath] = OfflineTrack(
        path: libraryPath,
        file: target.path,
        bytes: written,
        title: title,
        artist: artist,
        album: album,
        savedAt: DateTime.now(),
      );
      await _save();
      job.done = true;
      _jobs.remove(libraryPath);
      notifyListeners();
      return true;
    } catch (e) {
      job.error = '$e';
      _jobs.remove(libraryPath);
      // Close before deleting, and swallow what close() rethrows: a sink whose stream errored
      // hands that same error back here, and it is already being reported as job.error.
      try {
        await sink?.close();
      } catch (_) {/* the write already failed — this is only letting go of the handle */}
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {/* nothing to clean up */}
      notifyListeners();
      debugPrint('Offline download failed for $libraryPath: $e');
      return false;
    }
  }

  /// Stop a download that is still running.
  void cancel(String libraryPath) {
    if (!_jobs.containsKey(libraryPath)) return;
    _cancelled.add(libraryPath);
    // Ook uit de rij halen, anders begint hij alsnog zodra hij aan de beurt is — met een vlag die
    // zegt dat hij geannuleerd was. Dan zou "weghalen" een nummer terugbrengen.
    final wachtte = _wachtrij.indexWhere((r) => r.libraryPath == libraryPath);
    if (wachtte >= 0) {
      _wachtrij.removeAt(wachtte);
      _jobs.remove(libraryPath);
      notifyListeners();
    }
  }

  /// Take a track off this device. The PC's copy is untouched — this is the whole difference
  /// between "remove the download" and "delete the track", and they must never be confused.
  Future<void> remove(String libraryPath) async {
    cancel(libraryPath);
    final t = _tracks.remove(libraryPath);
    notifyListeners();
    if (t == null) return;
    try {
      final f = File(t.file);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('Offline file not deleted: $e');
    }
    await _save();
  }

  /// Everything off.
  Future<void> clear() async {
    final paths = _tracks.keys.toList();
    for (final p in paths) {
      await remove(p);
    }
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}
