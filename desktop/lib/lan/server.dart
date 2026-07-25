import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../library.dart';
import '../models.dart';
import '../online.dart';
import '../organize.dart';
import '../settings.dart';
import '../soulseek.dart';
import '../torbox.dart';
import 'cast_manager.dart';
import 'catalog.dart';
import 'dtos.dart';
import 'net.dart';
import 'pairing.dart';
import 'range.dart';
import 'state_store.dart';
import 'tokens.dart';
import 'transcode.dart';

/// The port the other devices look for. Fixed on purpose — an ephemeral port would mean every
/// restart hands out a different address, and anything a client saved would go stale.
const int kLanPort = 47820;

/// Serves this machine's library to the Mac, the iPad and the Shield.
///
/// It runs inside the app rather than as a separate service, and reads straight from the live
/// [LibraryStore]. That is the whole design: the covers you picked, the pressings you pinned and
/// the albums you merged are in those objects, so there is no second scan that could disagree
/// with what you see on screen here.
class LanServer {
  LanServer({
    required this.library,
    required this.token,
    required this.state,
    required this.pairing,
    this.port = kLanPort,
    this.version = '',
    this.online,
    this.soulseek,
    this.downloads,
    this.settings,
    GrantStore? grants,
  })  : grants = grants ?? GrantStore(),
        catalog = LanCatalog(library) {
    cast = CastManager(catalog: catalog, token: token, port: port);
  }

  final LibraryStore library;
  final LanCatalog catalog;

  /// Searching and downloading, done HERE on behalf of a Mac or an iPad.
  ///
  /// Nullable because the server is also constructed in tests that care only about the library,
  /// and because a PC with no TorBox key still shares its music perfectly well. The routes answer
  /// 503 rather than crashing when they are absent — a client can then say so.
  final OnlineService? online;
  final SoulseekService? soulseek;
  final DownloadManager? downloads;

  /// Needed by [LibraryStore.applyCorrection] — a hand-picked cover is written into the cover
  /// cache, and that lives where the settings say.
  final AppSettings? settings;

  /// Which devices may fetch anything, one token each. See `tokens.dart` — it deliberately knows
  /// nothing about who signed in, so this server keeps working with the internet unplugged.
  final GrantStore grants;
  final LanStateStore state;
  final PairingStore pairing;

  /// Sending music to a speaker or the TV. Lives on the PC so the audio goes straight from here
  /// to the speaker, and so every device gets the same destination list.
  late final CastManager cast;
  final Transcoder transcoder = Transcoder();
  final int port;
  final String version;
  String token;

  HttpServer? _http;

  bool get running => _http != null;

  /// The port actually listening. Equals [port] in the app; differs only when [port] is 0, which
  /// tests use to let the OS pick something free rather than fight the running app for 47820.
  int get boundPort => _http?.port ?? port;

  /// Starts listening. Returns null on success, or a message to show the user.
  Future<String?> start() async {
    if (_http != null) return null;
    try {
      // anyIPv4, not `anyIPv4Loopback` and not the default: binding the default address gives an
      // IPv6 socket, and on a network where the other devices only speak IPv4 every connection
      // then fails without a single log line. The Android receiver in the media app was bitten by
      // exactly this — see the note in that project's cast receiver.
      _http = await HttpServer.bind(InternetAddress.anyIPv4, port);
    } on SocketException catch (e) {
      return e.osError?.errorCode == 10048 || e.osError?.errorCode == 48
          ? 'Poort $port is al in gebruik door een ander programma.'
          : 'Kon niet starten op poort $port: ${e.osError?.message ?? e.message}';
    }
    _http!.autoCompress = false; // audio and covers are already compressed
    unawaited(_serve(_http!));
    return null;
  }

  Future<void> stop() async {
    final http = _http;
    _http = null;
    await http?.close(force: true);
  }

  /// Stop for good. Separate from [stop] so switching sharing off and on again doesn't leave the
  /// catalogue detached from the library and quietly serving a frozen snapshot.
  Future<void> dispose() async {
    await stop();
    cast.dispose();
    catalog.dispose();
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      // One bad request must never take the server — and with it the whole app — down.
      unawaited(_handle(request).catchError((Object e, StackTrace s) {
        debugPrint('LAN request failed (${request.uri.path}): $e');
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.close();
        } catch (_) {/* already closed or hung up */}
      }));
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Headers', 'Authorization, Content-Type, Range, If-None-Match')
      ..set('Access-Control-Allow-Methods', 'GET, POST, HEAD, OPTIONS')
      // Without this a browser client can't read the range headers it just asked for.
      ..set('Access-Control-Expose-Headers', 'Content-Range, Accept-Ranges, Content-Length, ETag');

    if (req.method == 'OPTIONS') {
      res.statusCode = HttpStatus.noContent;
      await res.close();
      return;
    }

    final path = req.uri.path;

    // Unauthenticated on purpose: this is how a device confirms it found the right machine, and
    // how the app itself checks whether a second copy is already running.
    if (path == '/health') {
      return _json(res, {
        'status': 'ok',
        'name': 'debridmusic-desktop',
        'version': version,
        'deviceName': Platform.localHostname,
        'trackCount': library.tracks.length,
        'albumCount': library.albums.length,
      });
    }

    // Also unauthenticated, necessarily — this is how a device that has no token gets one.
    if (path == '/pair') return _pair(req);

    if (!_authorized(req)) {
      res.statusCode = HttpStatus.unauthorized;
      return res.close();
    }

    switch (path) {
      case '/api/catalog':
        return _catalog(req);
      case '/api/library/artists':
        return _json(res, [for (final a in catalog.snapshot().catalog.artists) a.toJson()]);
      case '/api/library/albums':
        return _json(res, [for (final a in catalog.snapshot().catalog.albums) a.toJson()]);
      case '/api/library/tracks':
        return _tracks(req);
      case '/api/search':
        return _json(res, catalog.search(req.uri.queryParameters['q'] ?? '').toJson());
      case '/api/state':
        return _state(req);
      case '/api/state/ops':
        return _stateOps(req);
      case '/api/events':
        return _events(req);
      case '/api/cast/devices':
        return _json(res, await cast.devices());
      case '/api/cast/play':
        return _castPlay(req);
      case '/api/cast/control':
        return _castControl(req);
      case '/api/online/search':
        return _onlineSearch(req);
      case '/api/online/tracklist':
        return _onlineTracklist(req);
      case '/api/online/download':
        return _onlineDownload(req);
      case '/api/soulseek/search':
        return _soulseekSearch(req);
      case '/api/soulseek/download':
        return _soulseekDownload(req);
      case '/api/soulseek/download-album':
        return _soulseekDownloadAlbum(req);
      case '/api/jobs':
        return _json(res, {'jobs': jobsSnapshot()});
      case '/api/jobs/cancel':
        return _jobCancel(req);
      case '/api/jobs/clear':
        return _jobsClear(req);
      case '/api/config':
        return _config(req);
      case '/api/corrections':
        return _corrections(req);
      case '/api/move/plan':
        return _movePlan(req);
      case '/api/move/apply':
        return _moveApply(req);
    }

    if (path.startsWith('/stream/')) return _stream(req);
    if (path.startsWith('/art/')) return _art(req);

    res.statusCode = HttpStatus.notFound;
    return res.close();
  }

  bool _authorized(HttpRequest req) {
    final header = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final bearer = header.startsWith('Bearer ') ? header.substring(7).trim() : '';
    // The query form is not laziness: a UPnP renderer and an <audio> tag both fetch the URL
    // themselves and have nowhere to put a header.
    final query = req.uri.queryParameters['token'] ?? '';
    final offered = bearer.isNotEmpty ? bearer : query;
    if (offered.isEmpty) return false;

    // A per-device grant, or the one shared token this used to have. The legacy check stays and is
    // NOT rotated on upgrade: a device paired yesterday must keep working the moment this ships,
    // and unpairing everything at once is exactly what the old design was stuck with.
    if (grants.accepts(offered)) {
      if (grants.touch(offered)) unawaited(grants.save());
      return true;
    }
    return token.isNotEmpty && _constantTimeEquals(offered, token);
  }

  /// Not `==`. Comparing a secret with an early-exit comparison leaks, through timing, how much of
  /// a guess was right — which is the one thing a guesser needs.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> _catalog(HttpRequest req) async {
    final snap = catalog.snapshot();
    final res = req.response;
    // A client that already has this version gets 304 and no body. With a library of tens of
    // thousands of tracks that is the difference between a sync costing megabytes and costing
    // nothing, which matters when four devices re-check every time they wake up.
    if (req.headers.value(HttpHeaders.ifNoneMatchHeader) == snap.etag) {
      res.statusCode = HttpStatus.notModified;
      res.headers.set(HttpHeaders.etagHeader, snap.etag);
      return res.close();
    }
    res.statusCode = HttpStatus.ok;
    res.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')
      ..set(HttpHeaders.etagHeader, snap.etag);
    res.headers.contentLength = snap.json.length;
    res.add(snap.json);
    return res.close();
  }

  Future<void> _tracks(HttpRequest req) async {
    final all = catalog.snapshot().catalog.tracks;
    final albumId = req.uri.queryParameters['albumId'];
    final artistId = req.uri.queryParameters['artistId'];
    final filtered = all.where((t) =>
        (albumId == null || t.albumId == albumId) && (artistId == null || t.artistId == artistId));
    return _json(req.response, [for (final t in filtered) t.toJson()]);
  }

  /// Trade a six-digit code for the access token.
  ///
  /// Answers exactly the same way for a wrong code and for pairing not being open at all, so
  /// nothing on the network can work out whether a code is currently on screen.
  Future<void> _pair(HttpRequest req) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    final body = await utf8.decoder.bind(req).join();
    final decoded = jsonDecode(body.isEmpty ? '{}' : body);
    final map = decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
    if (!pairing.redeem((map['code'] ?? '').toString())) {
      req.response.statusCode = HttpStatus.forbidden;
      return req.response.close();
    }
    return _json(req.response, {
      'token': token,
      'name': Platform.localHostname,
      'trackCount': library.tracks.length,
    });
  }

  Future<void> _castPlay(HttpRequest req) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    final map = await _body(req);
    try {
      await cast.play(
        (map['deviceId'] ?? '') as String,
        [for (final id in (map['trackIds'] as List? ?? const [])) id.toString()],
        (map['index'] as int?) ?? 0,
      );
      return _json(req.response, {'ok': true});
    } catch (e) {
      // A speaker that has gone off the network, or a track that isn't there any more. The
      // client shows this, so it must read like something a person can act on.
      req.response.statusCode = HttpStatus.badRequest;
      return _json(req.response, {'error': '$e'});
    }
  }

  Future<void> _castControl(HttpRequest req) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    final map = await _body(req);
    try {
      await cast.control(
        (map['deviceId'] ?? '') as String,
        (map['action'] ?? '') as String,
        value: map['value'] as int?,
      );
      return _json(req.response, {'ok': true});
    } catch (e) {
      req.response.statusCode = HttpStatus.badRequest;
      return _json(req.response, {'error': '$e'});
    }
  }

  Future<Map<String, dynamic>> _body(HttpRequest req) async {
    final text = await utf8.decoder.bind(req).join();
    final decoded = jsonDecode(text.isEmpty ? '{}' : text);
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<void> _state(HttpRequest req) async {
    final since = int.tryParse(req.uri.queryParameters['since'] ?? '');
    // Nothing durable has changed since the client last looked. The position may well have, so
    // it rides along — it is a handful of bytes and saves a second round trip.
    if (since != null && since == state.rev) {
      return _json(req.response, {
        'rev': state.rev,
        'progressRev': state.progressRev,
        'unchanged': true,
        'progress': state.progress.toJson(),
      });
    }
    return _json(req.response, state.snapshot());
  }

  Future<void> _stateOps(HttpRequest req) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    final body = await utf8.decoder.bind(req).join();
    final decoded = jsonDecode(body.isEmpty ? '{}' : body);
    final map = decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
    final result = state.applyOps(
      (map['ops'] as List?) ?? const [],
      deviceId: (map['deviceId'] ?? '') as String,
      deviceName: (map['deviceName'] ?? '') as String,
    );
    return _json(req.response, result);
  }

  /// Server-sent events: the PC tells every device the moment something changes, instead of four
  /// devices asking every few seconds whether anything did.
  Future<void> _events(HttpRequest req) async {
    final res = req.response;
    res.statusCode = HttpStatus.ok;
    res.headers
      ..set(HttpHeaders.contentTypeHeader, 'text/event-stream; charset=utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set(HttpHeaders.connectionHeader, 'keep-alive')
      // Nginx and friends buffer by default, which turns an event stream into silence.
      ..set('X-Accel-Buffering', 'no');
    res.bufferOutput = false;

    void send(Map<String, dynamic> data) {
      try {
        res.write('data: ${jsonEncode(data)}\n\n');
      } catch (_) {/* client gone; the done-handler below cleans up */}
    }

    send({'rev': state.rev, 'progressRev': state.progressRev, 'progress': state.progress.toJson()});

    final sub = state.changes.listen(send);
    // A silent connection is indistinguishable from a dead one, and home routers drop idle TCP.
    final beat = Timer.periodic(const Duration(seconds: 20), (_) {
      try {
        res.write(': ping\n\n');
      } catch (_) {}
    });

    // Held open until the client hangs up.
    await res.done.catchError((Object _) {});
    await sub.cancel();
    beat.cancel();
  }

  Future<void> _stream(HttpRequest req) async {
    // `/stream/<id>` and `/stream/<id>.flac` are the same track. The extension is there for the
    // Apple clients: AVFoundation types an asset by its path, and refuses one it can't place.
    final raw = Uri.decodeComponent(req.uri.pathSegments.last);
    final dot = raw.lastIndexOf('.');
    final id = dot > 0 ? raw.substring(0, dot) : raw;

    final track = catalog.track(id);
    if (track == null) {
      req.response.statusCode = HttpStatus.notFound;
      return req.response.close();
    }
    final file = File(track.path);
    if (!await file.exists()) {
      req.response.statusCode = HttpStatus.notFound;
      return req.response.close();
    }

    // `?maxRate=` is how a speaker with a ceiling gets a version it can actually play — Sonos
    // stops at 48 kHz and skips anything above rather than downsampling it. Only the cast path
    // ever asks for this; every other client gets the file untouched.
    final maxRate = int.tryParse(req.uri.queryParameters['maxRate'] ?? '');
    if (maxRate != null && track.sampleRate > maxRate) {
      return _streamResampled(req, file, maxRate);
    }
    return serveFile(req, file, contentType: mimeForExt(track.ext));
  }

  /// Pipe the track through ffmpeg on its way out.
  ///
  /// No Content-Length and no Range: the converted size isn't known until it's done. Renderers
  /// accept a chunked audio stream — the cost is that you cannot seek within a cast hi-res
  /// track, which beats it not playing at all.
  Future<void> _streamResampled(HttpRequest req, File file, int maxRate) async {
    final process = await transcoder.resample(file, maxSampleRate: maxRate);
    if (process == null) {
      // No ffmpeg — send the original and let the speaker decide. On a Sonos that means the
      // track is skipped, but silently degrading is better than refusing every hi-res track.
      return serveFile(req, file, contentType: 'audio/flac');
    }
    final res = req.response;
    res.statusCode = HttpStatus.ok;
    res.headers
      ..set(HttpHeaders.contentTypeHeader, 'audio/flac')
      ..set(HttpHeaders.acceptRangesHeader, 'none');
    // Report what ffmpeg says instead of discarding it. Draining this blind is how an empty
    // stream ("resampling engine unavailable") looked like a mystery rather than a one-line fix.
    unawaited(process.stderr.transform(utf8.decoder).forEach((line) {
      final text = line.trim();
      if (text.isNotEmpty) debugPrint('ffmpeg: $text');
    }));
    try {
      await res.addStream(process.stdout);
    } catch (_) {
      // The speaker hung up — normal when you skip a track.
    }
    process.kill();
    await res.close();
  }

  // ── Searching and downloading, on behalf of another device ─────────────────
  //
  // The Mac and the iPad have no TorBox key, no Soulseek login and, on an iPad, nowhere to put a
  // music library anyway. So they ask this PC to do it: the search runs here, the download lands
  // here, and the finished album comes back to everyone through the catalogue that already syncs.
  // That also means one set of credentials, on the machine that already had them.

  /// What the job list looks like to another device. Only the fields a progress row shows — the
  /// live peer sockets and the fallback candidates are this machine's business.
  List<Map<String, dynamic>> jobsSnapshot() => [
        for (final j in downloads?.jobs ?? const <DownloadJob>[])
          {
            'name': j.name,
            'key': j.key,
            'progress': j.progress,
            'status': j.status,
            'detail': j.detail,
            'queuePlace': j.queuePlace,
            'canCancel': j.canCancel,
            'trackKey': j.trackKey,
          },
      ];

  Future<Map<String, dynamic>?> _jsonBody(HttpRequest req) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      await req.response.close();
      return null;
    }
    final text = await utf8.decoder.bind(req).join();
    final decoded = jsonDecode(text.isEmpty ? '{}' : text);
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// 503 with a sentence a person can read, not a bare status code: on the iPad this is the
  /// difference between "the pc can't do that" and a spinner that never stops.
  Future<void> _unavailable(HttpRequest req, String why) =>
      _json(req.response, {'error': why}, status: HttpStatus.serviceUnavailable);

  Future<void> _onlineSearch(HttpRequest req) async {
    final service = online;
    if (service == null) return _unavailable(req, 'Deze pc kan niet online zoeken.');
    final q = req.uri.queryParameters['q'] ?? '';
    if (q.trim().isEmpty) return _json(req.response, {'results': []});
    try {
      final results = await service.search(q);
      return _json(req.response, {'results': [for (final r in results) r.toJson()]});
    } catch (e) {
      return _unavailable(req, 'Zoeken mislukte op de pc: $e');
    }
  }

  Future<void> _onlineTracklist(HttpRequest req) async {
    final service = online;
    if (service == null) return _unavailable(req, 'Deze pc kan niet online zoeken.');
    final body = await _jsonBody(req);
    if (body == null) return;
    try {
      final (torrent, files) = await service.tracklist(SearchResult.fromJson(body));
      return _json(req.response, {
        'torrentId': torrent.id,
        'files': [
          for (final f in files)
            {'id': f.id, 'name': f.name, 'shortName': f.shortName, 'size': f.size, 'mimeType': f.mimeType},
        ],
      });
    } catch (e) {
      return _unavailable(req, 'De tracklijst ophalen mislukte: $e');
    }
  }

  Future<void> _onlineDownload(HttpRequest req) async {
    final manager = downloads;
    if (manager == null) return _unavailable(req, 'Deze pc kan niet downloaden.');
    final body = await _jsonBody(req);
    if (body == null) return;
    startTorrentDownload(body);
    return _json(req.response, {'ok': true});
  }

  Future<void> _soulseekSearch(HttpRequest req) async {
    final service = soulseek;
    if (service == null || !service.available) {
      return _unavailable(req, 'Op deze pc is Soulseek niet ingesteld.');
    }
    final q = req.uri.queryParameters['q'] ?? '';
    if (q.trim().isEmpty) return _json(req.response, {'files': []});
    try {
      final files = await service.search(q);
      return _json(req.response, {'files': [for (final f in files) f.toJson()]});
    } catch (e) {
      return _unavailable(req, 'Soulseek zoeken mislukte: $e');
    }
  }

  // ── Starting a download from a request body ────────────────────────────────
  //
  // Public because the queue worker replays exactly these bodies when the PC comes back online
  // after a device asked for something while it was off. Sharing the parsing is the point: a
  // download that was queued must land the same way as one asked for live, including the
  // authority tags — and two copies of this parsing would eventually disagree about that.

  /// The body of `POST /api/online/download`.
  void startTorrentDownload(Map<String, dynamic> body) {
    final manager = downloads;
    if (manager == null) return;
    final fileId = (body['fileId'] as num?)?.toInt();
    // Deliberately not awaited: enqueue starts the work and returns, and the caller watches
    // /api/jobs. Holding a request open for a download would time out long before it finished.
    manager.enqueue(SearchResult.fromJson(body), fileId: fileId);
  }

  /// The body of `POST /api/soulseek/download`. False when nothing usable was in it.
  Future<bool> startSoulseekDownload(Map<String, dynamic> body) async {
    final manager = downloads;
    if (manager == null) return false;
    final candidates = <SoulseekFile>[];
    for (final c in (body['candidates'] as List? ?? const [])) {
      if (c is! Map<String, dynamic>) continue;
      final f = SoulseekFile.fromJson(c);
      if (f != null) candidates.add(f);
    }
    if (candidates.isEmpty) return false;
    return manager.enqueueSoulseekBest(candidates,
        key: body['key'] as String?, authority: _authorityOf(body));
  }

  /// The body of `POST /api/soulseek/download-album`. How many tracks were started.
  Future<int> startSoulseekAlbumDownload(Map<String, dynamic> body) async {
    final manager = downloads;
    if (manager == null) return 0;
    final tracks = <List<SoulseekFile>>[];
    for (final t in (body['tracks'] as List? ?? const [])) {
      if (t is! List) continue;
      final files = <SoulseekFile>[];
      for (final c in t) {
        if (c is! Map<String, dynamic>) continue;
        final f = SoulseekFile.fromJson(c);
        if (f != null) files.add(f);
      }
      tracks.add(files);
    }
    if (tracks.isEmpty) return 0;
    // Index-aligned with `tracks`, so a missing entry is a null rather than a shift — a shift
    // would file every remaining track under the previous one's identity.
    final wire = body['authorities'] as List? ?? const [];
    final authorities = <TrackTags?>[
      for (var i = 0; i < tracks.length; i++)
        if (i < wire.length && wire[i] is Map<String, dynamic>)
          TrackTags.fromJson(wire[i] as Map<String, dynamic>)
        else
          null
    ];
    return manager.enqueueSoulseekAlbum(tracks, authorities: authorities);
  }

  /// What the device says this track IS, when it says anything.
  ///
  /// Optional on purpose: a client from before this existed sends no authority, and must keep
  /// working exactly as it did. Soulseek supplies the audio; whoever asked for it supplies the
  /// identity — and if nobody does, placeFileDetailed falls back to the peer's own tags as before.
  static TrackTags? _authorityOf(Map<String, dynamic> body) {
    final a = body['authority'];
    return a is Map<String, dynamic> ? TrackTags.fromJson(a) : null;
  }

  Future<void> _soulseekDownload(HttpRequest req) async {
    final manager = downloads;
    if (manager == null) return _unavailable(req, 'Deze pc kan niet downloaden.');
    final body = await _jsonBody(req);
    if (body == null) return;
    try {
      final started = await startSoulseekDownload(body);
      return _json(req.response, {'ok': started});
    } catch (e) {
      return _unavailable(req, '$e');
    }
  }

  /// A whole album at once, asked for by a paired device.
  ///
  /// `tracks` is one list of candidate copies per track, `authorities` runs alongside it by index —
  /// the same shape the local call takes, so the PC does here exactly what it does for itself.
  Future<void> _soulseekDownloadAlbum(HttpRequest req) async {
    final manager = downloads;
    if (manager == null) return _unavailable(req, 'Deze pc kan niet downloaden.');
    final body = await _jsonBody(req);
    if (body == null) return;
    try {
      final started = await startSoulseekAlbumDownload(body);
      return _json(req.response, {'started': started});
    } catch (e) {
      return _unavailable(req, '$e');
    }
  }

  Future<void> _jobCancel(HttpRequest req) async {
    final manager = downloads;
    if (manager == null) return _unavailable(req, 'Deze pc kan niet downloaden.');
    final body = await _jsonBody(req);
    if (body == null) return;
    final key = body['key'] as String?;
    final name = body['name'] as String?;
    // By key when there is one, otherwise by name: a loose search hit has no track identity, and
    // its row still needs a stop button that works.
    final job = key != null
        ? manager.jobByKey(key)
        : manager.jobs.cast<DownloadJob?>().firstWhere((j) => j?.name == name, orElse: () => null);
    if (job != null) manager.cancelJob(job);
    return _json(req.response, {'ok': job != null});
  }

  Future<void> _jobsClear(HttpRequest req) async {
    final manager = downloads;
    if (manager == null) return _unavailable(req, 'Deze pc kan niet downloaden.');
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    manager.clearFinished();
    return _json(req.response, {'ok': true});
  }

  /// Metadata edited on another device, applied HERE.
  ///
  /// The album is named by the id this PC issued, so there is no guessing about which "Millennium"
  /// was meant when the library holds two pressings of it. The change lands in the same
  /// [LibraryStore] the PC itself edits, which means it reaches every device the ordinary way:
  /// the catalogue fingerprint changes and the next poll picks it up.
  /// The read-only API keys a paired device needs to look things up for itself.
  ///
  /// Only these two, and that is the whole rule: a Discogs token and a Last.fm key read public
  /// databases and are revoked in one click. Passwords are NOT here — the Soulseek and RuTracker
  /// logins sign into accounts, and the calls that need them already run on this machine anyway.
  ///
  /// Sent on every connect rather than once at pairing, so changing a token here reaches the
  /// devices by itself instead of leaving them on a key that stopped working.
  Future<void> _config(HttpRequest req) async {
    final config = settings;
    if (config == null) return _json(req.response, const {});
    return _json(req.response, {
      'discogsToken': config.discogsToken,
      'lastfmKey': config.lastfmKey,
    });
  }

  Future<void> _corrections(HttpRequest req) async {
    final config = settings;
    if (config == null) return _unavailable(req, 'Deze pc kan geen wijzigingen aannemen.');
    final body = await _jsonBody(req);
    if (body == null) return;

    final op = (body['op'] ?? '') as String;
    final album = body['albumId'] is String ? catalog.album(body['albumId'] as String) : null;
    if (op != 'removeTracks' && album == null) {
      // The client is looking at a catalogue this PC has moved on from — say so, rather than
      // silently editing the wrong record.
      return _json(req.response, {'error': 'Dat album staat hier niet (meer).'},
          status: HttpStatus.notFound);
    }

    try {
      switch (op) {
        case 'correction':
          final coverB64 = body['cover'] as String?;
          await library.applyCorrection(
            album!,
            config,
            artist: body['artist'] as String?,
            albumTitle: body['albumTitle'] as String?,
            title: body['title'] as String?,
            coverBytes: coverB64 == null || coverB64.isEmpty ? null : base64Decode(coverB64),
            discogsRelease: (body['discogsRelease'] as num?)?.toInt(),
            mbid: body['mbid'] as String?,
          );
        case 'merge':
          await library.mergeEditions(album!);
        case 'unmerge':
          await library.unmergeEditions(album!);
        case 'removeTracks':
          final paths = <String>[];
          for (final id in (body['trackIds'] as List? ?? const [])) {
            final t = id is String ? catalog.track(id) : null;
            if (t != null) paths.add(t.path);
          }
          if (paths.isEmpty) return _json(req.response, {'ok': false, 'reason': 'niets gevonden'});
          await library.removeTracks(paths, fromDisk: body['fromDisk'] == true);
        default:
          return _json(req.response, {'error': 'Onbekende bewerking: $op'},
              status: HttpStatus.badRequest);
      }
    } catch (e) {
      return _unavailable(req, 'De pc kon dat niet toepassen: $e');
    }
    return _json(req.response, {'ok': true});
  }

  /// What moving these tracks would do on disk — worked out HERE, where the files are.
  ///
  /// Its own call before anything is applied, because the dialog on the other device exists to say
  /// what will happen to which file. A client cannot work that out: it has no folders, no idea
  /// which copy is better, and no way to know that a name is already taken.
  Future<void> _movePlan(HttpRequest req) async {
    final body = await _jsonBody(req);
    if (body == null) return;
    final target = body['albumId'] is String ? catalog.album(body['albumId'] as String) : null;
    if (target == null) {
      return _json(req.response, {'error': 'Dat album staat hier niet (meer).'},
          status: HttpStatus.notFound);
    }
    final tracks = _tracksFor(body['trackIds']);
    if (tracks.isEmpty) return _json(req.response, {'items': []});
    final plan = library.planMove(tracks, target);
    // Built once and turned round: the plan is keyed by track, the client speaks in ids, and doing
    // this lookup per item would walk the whole library for every file being moved.
    final idByPath = {for (final e in catalog.snapshot().trackById.entries) e.value.path: e.key};
    return _json(req.response, {
      'folder': target.tracks.isEmpty ? null : File(target.tracks.first.path).parent.path,
      'items': [
        for (final p in plan)
          {
            'trackId': idByPath[p.track.path],
            'from': p.from,
            'to': p.to,
            'fate': p.fate.name,
          },
      ],
    });
  }

  /// Apply the plan the user actually read.
  ///
  /// The approved `to` and `fate` come back with the request rather than being worked out again:
  /// re-planning here would let the folder change between the screen someone agreed to and the
  /// files that move.
  Future<void> _moveApply(HttpRequest req) async {
    final config = settings;
    if (config == null) return _unavailable(req, 'Deze pc kan geen wijzigingen aannemen.');
    final body = await _jsonBody(req);
    if (body == null) return;
    final target = body['albumId'] is String ? catalog.album(body['albumId'] as String) : null;
    if (target == null) {
      return _json(req.response, {'error': 'Dat album staat hier niet (meer).'},
          status: HttpStatus.notFound);
    }

    final byId = catalog.snapshot().trackById;
    final approved = <MovePlan>[];
    for (final item in (body['plan'] as List? ?? const [])) {
      if (item is! Map<String, dynamic>) continue;
      final track = byId[item['trackId'] as String? ?? ''];
      if (track == null) continue;
      approved.add(MovePlan(
        track,
        track.path,
        item['to'] as String?,
        MoveFate.values.firstWhere((f) => f.name == item['fate'], orElse: () => MoveFate.moves),
      ));
    }
    final tracks = approved.isNotEmpty
        ? [for (final p in approved) p.track]
        : _tracksFor(body['trackIds']);
    if (tracks.isEmpty) return _json(req.response, {'moved': 0});

    try {
      final moved = await library.moveTracksToAlbum(tracks, target, config,
          moveFiles: body['moveFiles'] != false,
          plan: approved.isEmpty ? null : approved);
      return _json(req.response, {'moved': moved});
    } catch (e) {
      return _unavailable(req, 'De pc kon dat niet verplaatsen: $e');
    }
  }

  List<Track> _tracksFor(Object? ids) {
    final out = <Track>[];
    for (final id in (ids as List? ?? const [])) {
      final t = id is String ? catalog.track(id) : null;
      if (t != null) out.add(t);
    }
    return out;
  }

  Future<void> _art(HttpRequest req) async {
    final ref = Uri.decodeComponent(req.uri.pathSegments.last);
    final bytes = catalog.artwork(ref);
    final res = req.response;
    if (bytes == null || bytes.isEmpty) {
      // Not an error: a cover the enricher hasn't reached yet simply isn't there, and the client
      // shows its placeholder.
      res.statusCode = HttpStatus.notFound;
      return res.close();
    }
    res.statusCode = HttpStatus.ok;
    res.headers
      ..set(HttpHeaders.contentTypeHeader, _imageType(bytes))
      ..set(HttpHeaders.cacheControlHeader, 'private, max-age=3600');
    res.headers.contentLength = bytes.length;
    if (req.method != 'HEAD') res.add(bytes);
    return res.close();
  }

  /// [status] is a parameter and not always 200 because it used to be hardcoded here, which
  /// quietly turned every error body into a successful empty answer: a client asking a PC that
  /// cannot search got `{"error": "..."}` with a 200, read no results in it, and showed "niets
  /// gevonden" instead of the reason.
  Future<void> _json(HttpResponse res, Object body, {int status = HttpStatus.ok}) async {
    final bytes = utf8.encode(jsonEncode(body));
    res.statusCode = status;
    res.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    res.headers.contentLength = bytes.length;
    res.add(bytes);
    return res.close();
  }

  /// Covers come from tags and from the web, so they are whatever the source was. Sniff the magic
  /// bytes rather than assume JPEG — a PNG served as JPEG renders as nothing on some clients.
  static String _imageType(List<int> b) {
    if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'image/gif';
    if (b.length > 11 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
    return 'image/jpeg';
  }

  /// The URLs to hand to the other devices, best first.
  Future<List<String>> addresses() async =>
      [for (final ip in await lanAddresses()) 'http://$ip:$port'];
}

/// A fresh access token. Generated once and kept, so a device stays paired across restarts.
String generateLanToken() {
  final rnd = Random.secure();
  return List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
