import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../library.dart';
import 'cast_manager.dart';
import 'catalog.dart';
import 'dtos.dart';
import 'net.dart';
import 'pairing.dart';
import 'range.dart';
import 'state_store.dart';
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
  }) : catalog = LanCatalog(library) {
    cast = CastManager(catalog: catalog, token: token, port: port);
  }

  final LibraryStore library;
  final LanCatalog catalog;
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
    return token.isNotEmpty && (bearer == token || query == token);
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

  Future<void> _json(HttpResponse res, Object body) async {
    final bytes = utf8.encode(jsonEncode(body));
    res.statusCode = HttpStatus.ok;
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
