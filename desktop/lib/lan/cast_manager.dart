import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'catalog.dart';
import 'dtos.dart';
import 'net.dart';
import 'transcode.dart';
import 'upnp.dart';

/// The Shield running the DebridMusic TV app.
///
/// Not a UPnP renderer — it takes a plain POST and hands the URL to ExoPlayer, which is the whole
/// reason to send music there rather than to a speaker: bit-perfect FLAC out of the HDMI, with no
/// ceiling on sample rate.
class ShieldTarget {
  const ShieldTarget({required this.host, required this.name});

  final String host;
  final String name;

  /// 8124, not 8123 — the Debrid **Media** app already listens on 8123 on the same Shield.
  static const port = 8124;

  String get id => 'shield:$host';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'model': 'Android TV',
        'manufacturer': 'DebridMusic',
        'kind': 'shield',
        'maxSampleRate': 0,
      };
}

/// Sends music to a speaker or the TV, and keeps it going.
///
/// The PC does this, not the iPad. Three reasons, in order of how much they matter:
/// the audio then goes straight from here to the speaker instead of being relayed by whatever
/// you happened to tap on; one implementation serves every device in the house; and it sidesteps
/// Apple's multicast entitlement, which SSDP discovery from an iPad would otherwise need.
class CastManager {
  CastManager({
    required this.catalog,
    required this.token,
    required this.port,
    UpnpControlPoint? upnp,
    Transcoder? transcoder,
  })  : _upnp = upnp ?? UpnpControlPoint(),
        _transcoder = transcoder ?? Transcoder();

  final LanCatalog catalog;
  final UpnpControlPoint _upnp;
  final Transcoder _transcoder;
  final int port;
  String token;

  Map<String, Renderer> _renderers = {};
  List<ShieldTarget> _shields = [];

  _Session? _session;
  Timer? _advance;

  /// Every place the music can go, this device excluded.
  Future<List<Map<String, dynamic>>> devices({bool refresh = true}) async {
    if (refresh || _renderers.isEmpty) {
      final found = await _upnp.discover();
      _renderers = {for (final r in found) r.id: r};
      _shields = await _findShields();
    }
    return [
      for (final r in _renderers.values) r.toJson(),
      for (final s in _shields) s.toJson(),
    ];
  }

  /// Ask the LAN whether a Shield running the TV app is listening.
  ///
  /// A direct probe of the /24 rather than mDNS: the Shield's receiver is a bare socket with no
  /// service advertisement, and on a home network 254 parallel pings with a short timeout finish
  /// in under a second.
  Future<List<ShieldTarget>> _findShields() async {
    final own = await primaryLanAddress();
    if (own == null) return [];
    final prefix = own.split('.').take(3).join('.');
    final found = <ShieldTarget>[];
    await Future.wait([
      for (var i = 1; i < 255; i++)
        () async {
          final host = '$prefix.$i';
          if (host == own) return;
          final name = await _pingShield(host);
          if (name != null) found.add(ShieldTarget(host: host, name: name));
        }()
    ]);
    found.sort((a, b) => a.host.compareTo(b.host));
    return found;
  }

  Future<String?> _pingShield(String host) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 600);
    try {
      final request = await client.getUrl(Uri.parse('http://$host:${ShieldTarget.port}/ping'));
      final response = await request.close().timeout(const Duration(milliseconds: 900));
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      // The media app answers on 8123 with its own name; be sure this is the music receiver.
      if (!body.contains('debridmusic')) return null;
      return 'Shield ($host)';
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // ── Playing ──────────────────────────────────────────────────────────────

  /// Start [trackIds] on [deviceId] at [index].
  Future<void> play(String deviceId, List<String> trackIds, int index) async {
    if (trackIds.isEmpty) throw ArgumentError('nothing to play');
    _advance?.cancel();

    final shield = _shields.where((s) => s.id == deviceId).firstOrNull;
    if (shield != null) {
      await _playOnShield(shield, trackIds, index);
      return;
    }

    final renderer = await _renderer(deviceId);
    _session = _Session(renderer: renderer, queue: trackIds, index: index.clamp(0, trackIds.length - 1));
    await _openCurrent();
    // The renderer plays one track; something has to notice it ended and send the next.
    _advance = Timer.periodic(const Duration(seconds: 5), (_) => _maybeAdvance());
  }

  /// The Shield gets the whole queue at once — it has a real player and can manage its own gaps.
  Future<void> _playOnShield(ShieldTarget shield, List<String> trackIds, int index) async {
    final base = await lanAddressFor(shield.host);
    if (base == null) throw StateError('no route to ${shield.host}');
    final tracks = [for (final id in trackIds) catalog.track(id)];
    final urls = <String>[];
    for (var i = 0; i < trackIds.length; i++) {
      final track = tracks[i];
      if (track == null) continue;
      urls.add('http://$base:$port/stream/${trackIds[i]}.${track.ext}?token=$token');
    }
    if (urls.isEmpty) throw StateError('none of those tracks are in the library');

    final first = tracks[index.clamp(0, tracks.length - 1)];
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('http://${shield.host}:${ShieldTarget.port}/play'));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      // Same reason as the SOAP calls: the Shield's receiver reads Content-Length to know how
      // much body to expect, and a chunked request would arrive as an empty one.
      final payload = utf8.encode(jsonEncode({
        'streamUrls': urls,
        'index': index.clamp(0, urls.length - 1),
        'title': first?.title ?? '',
        'artist': first?.artist ?? '',
        'album': first?.album ?? '',
      }));
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close().timeout(const Duration(seconds: 8));
      await response.drain<void>();
      if (response.statusCode != 200) {
        throw StateError('de Shield weigerde het (HTTP ${response.statusCode})');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _openCurrent() async {
    final session = _session;
    if (session == null) return;
    final id = session.queue.elementAtOrNull(session.index);
    final track = id == null ? null : catalog.track(id);
    if (id == null || track == null) return;

    final url = await _streamUrlFor(id, track.ext, session.renderer, track.sampleRate);
    await _upnp.playUrl(
      session.renderer,
      url,
      title: track.title,
      artist: track.artist,
      album: track.album,
      mime: mimeForExt(track.ext),
      artUrl: await _artUrlFor(id, session.renderer),
    );
    session.startedAt = DateTime.now();

    // Hand the renderer the next one straight away, so the gap between two songs is the
    // speaker's own and not a round trip through here.
    final nextId = session.queue.elementAtOrNull(session.index + 1);
    final nextTrack = nextId == null ? null : catalog.track(nextId);
    if (nextId != null && nextTrack != null) {
      final nextUrl = await _streamUrlFor(nextId, nextTrack.ext, session.renderer, nextTrack.sampleRate);
      await _upnp.setNextUrl(
        session.renderer,
        nextUrl,
        title: nextTrack.title,
        artist: nextTrack.artist,
        album: nextTrack.album,
        mime: mimeForExt(nextTrack.ext),
      );
    }
  }

  /// The URL to hand the speaker — converted first when the speaker cannot take the original.
  Future<String> _streamUrlFor(String id, String ext, Renderer renderer, int sampleRate) async {
    final base = await lanAddressFor(renderer.host);
    final ceiling = renderer.maxSampleRate;
    // Sonos stops at 48 kHz and SKIPS anything higher — no error, no sound, just nothing. Send
    // it through the converter rather than let a hi-res album play as silence.
    if (ceiling > 0 && sampleRate > ceiling && _transcoder.available) {
      return 'http://$base:$port/stream/$id.flac?token=$token&maxRate=$ceiling';
    }
    return 'http://$base:$port/stream/$id.$ext?token=$token';
  }

  Future<String?> _artUrlFor(String id, Renderer renderer) async {
    final track = catalog.track(id);
    if (track == null) return null;
    final snapshot = catalog.snapshot();
    final dto = snapshot.catalog.tracks.where((t) => t.id == id).firstOrNull;
    if (dto?.artworkRef == null) return null;
    final base = await lanAddressFor(renderer.host);
    return 'http://$base:$port/art/${dto!.artworkRef}?token=$token';
  }

  /// Move to the next track once the speaker says it has finished.
  Future<void> _maybeAdvance() async {
    final session = _session;
    if (session == null) return;
    // Give the renderer a moment after a start before believing "STOPPED" — a Sonos reports
    // exactly that for a second or two while it fetches the first bytes.
    if (DateTime.now().difference(session.startedAt) < const Duration(seconds: 8)) return;

    final state = await _upnp.transportState(session.renderer);
    if (state == null || !state.isStopped) return;
    if (session.index + 1 >= session.queue.length) {
      _advance?.cancel();
      _session = null;
      return;
    }
    session.index++;
    await _openCurrent();
  }

  Future<void> control(String deviceId, String action, {int? value}) async {
    final shield = _shields.where((s) => s.id == deviceId).firstOrNull;
    if (shield != null) {
      if (action == 'stop') await _postShield(shield, '/stop');
      return;
    }
    final renderer = await _renderer(deviceId);
    switch (action) {
      case 'play':
        await _upnp.play(renderer);
      case 'pause':
        await _upnp.pause(renderer);
      case 'stop':
        _advance?.cancel();
        _session = null;
        await _upnp.stop(renderer);
      case 'next':
        final session = _session;
        if (session != null && session.index + 1 < session.queue.length) {
          session.index++;
          await _openCurrent();
        }
      case 'previous':
        final session = _session;
        if (session != null && session.index > 0) {
          session.index--;
          await _openCurrent();
        }
      case 'volume':
        await _upnp.setVolume(renderer, value ?? 50);
      default:
        throw ArgumentError('unknown action: $action');
    }
  }

  Future<void> _postShield(ShieldTarget shield, String path) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('http://${shield.host}:${ShieldTarget.port}$path'));
      final response = await request.close().timeout(const Duration(seconds: 5));
      await response.drain<void>();
    } catch (e) {
      debugPrint('shield $path failed: $e');
    } finally {
      client.close(force: true);
    }
  }

  Future<Renderer> _renderer(String id) async {
    final known = _renderers[id];
    if (known != null) return known;
    await devices();
    final found = _renderers[id];
    if (found == null) throw StateError('Die speaker is niet (meer) op het netwerk.');
    return found;
  }

  void dispose() {
    _advance?.cancel();
    _advance = null;
  }
}

class _Session {
  _Session({required this.renderer, required this.queue, required this.index});

  final Renderer renderer;
  final List<String> queue;
  int index;
  DateTime startedAt = DateTime.now();
}

extension _ElementAtOrNull<E> on List<E> {
  E? elementAtOrNull(int index) => (index >= 0 && index < length) ? this[index] : null;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
