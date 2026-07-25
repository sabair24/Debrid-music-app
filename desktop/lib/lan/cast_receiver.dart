/// The other end of casting: this device being told what to play.
///
/// The PC scans the network for anything answering on this port and offers it as a target. The
/// point of sending music HERE rather than to a speaker is what happens next — the URL goes to
/// libmpv and out over HDMI untouched, with no ceiling on sample rate and no re-encoding. A
/// Chromecast would not do that: it caps or transcodes.
///
/// Ported from the Kotlin app's CastReceiverServer, and deliberately the same wire contract —
/// `/ping`, `/play`, `/stop` with the same JSON — because the sender is the PC and the PC is not
/// changing. That is also what lets the Kotlin app be deleted without the feature going with it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models.dart';

/// Where the sender looks. Fixed rather than announced: the PC probes a /24 in under a second,
/// and a fixed port needs no service discovery on a box that has none.
const int kCastReceiverPort = 8124;

class CastReceiver {
  CastReceiver({required this.onPlay, required this.onStop, required this.deviceName});

  /// Hand a queue of stream URLs to the player. Called AFTER the sender has been answered.
  final void Function(List<Track> tracks, int index) onPlay;
  final VoidCallback onStop;

  /// What this device calls itself in the sender's list.
  final String Function() deviceName;

  HttpServer? _server;

  bool get listening => _server != null;

  /// Start listening. Never throws: a device that cannot open the port is a device you cannot cast
  /// to, which is a disappointment — not a reason for the app not to start.
  Future<void> start() async {
    if (_server != null) return;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, kCastReceiverPort);
      _server = server;
      server.listen(_handle, onError: (Object e) => debugPrint('Cast receiver error: $e'));
      debugPrint('Cast receiver listening on $kCastReceiverPort');
    } catch (e) {
      debugPrint('Cast receiver could not start: $e');
    }
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      switch (req.uri.path) {
        case '/ping':
          await _json(req, {'app': 'debridmusic', 'ready': true, 'name': deviceName()});
        case '/play':
          if (req.method != 'POST') return _notFound(req);
          final body = await utf8.decoder.bind(req).join();
          final decoded = jsonDecode(body);
          if (decoded is! Map<String, dynamic>) {
            return _json(req, {'error': 'empty request'}, status: HttpStatus.badRequest);
          }
          final urls = [
            for (final u in (decoded['streamUrls'] as List? ?? const [])) '$u',
          ]..removeWhere((u) => u.isEmpty);
          if (urls.isEmpty) {
            return _json(req, {'error': 'empty request'}, status: HttpStatus.badRequest);
          }

          // Answered BEFORE playing. Starting playback pulls the first bytes over the network, and
          // a sender waiting on that reads as "the TV is not responding" when it is simply busy
          // doing what was asked.
          await _json(req, {'ok': true});

          final title = (decoded['title'] ?? '').toString();
          final artist = (decoded['artist'] ?? '').toString();
          final album = (decoded['album'] ?? '').toString();
          final index = ((decoded['index'] as num?)?.toInt() ?? 0).clamp(0, urls.length - 1);

          // The sender names only the track it starts on — it has the catalogue, this end does
          // not. The rest carry the URL as their title, which is never shown: the player screen
          // reads the album back from the library by path, and these paths ARE library paths.
          final tracks = <Track>[
            for (var i = 0; i < urls.length; i++)
              Track(
                path: urls[i],
                title: i == index && title.isNotEmpty ? title : _nameFrom(urls[i]),
                artist: i == index ? artist : '',
                album: i == index ? album : '',
                isFlac: urls[i].contains('.flac'),
              ),
          ];
          onPlay(tracks, index);
        case '/stop':
          if (req.method != 'POST') return _notFound(req);
          await _json(req, {'ok': true});
          onStop();
        default:
          await _notFound(req);
      }
    } catch (e) {
      debugPrint('Cast request failed: $e');
      try {
        await _json(req, {'error': '$e'}, status: HttpStatus.badRequest);
      } catch (_) {/* the response is already gone */}
    }
  }

  /// A readable stand-in for a title, from the last path segment.
  static String _nameFrom(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final last = path.split('/').last;
    final dot = last.lastIndexOf('.');
    return dot > 0 ? last.substring(0, dot) : last;
  }

  Future<void> _notFound(HttpRequest req) =>
      _json(req, {'error': 'not found'}, status: HttpStatus.notFound);

  Future<void> _json(HttpRequest req, Object body, {int status = HttpStatus.ok}) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }
}
