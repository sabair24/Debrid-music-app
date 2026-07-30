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

/// The subnets to sweep for a television, from every address this machine has.
///
/// De-duplicated: two addresses on one subnet is one subnet. A plain function so the rule can be
/// stated in a test — the bug this exists for raises nothing and logs nothing, it just returns an
/// empty list as confidently as a correct search would.
Set<String> sweepPrefixes(Iterable<String> addresses) =>
    {for (final a in addresses) a.split('.').take(3).join('.')};

/// Ask one host whether the music receiver is listening, and what it calls itself.
///
/// Null for anything that is not ours: a closed port, some other web server, or the Debrid **Media**
/// app — which lives on the same television and answers the same shape one port down. Offering that
/// as a speaker would start a video player when somebody picked a place to listen.
Future<String?> probeShield(String host, {int port = ShieldTarget.port}) async {
  final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 600);
  try {
    final request = await client.getUrl(Uri.parse('http://$host:$port/ping'));
    final response = await request.close().timeout(const Duration(milliseconds: 900));
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join();
    if (!body.contains('debridmusic')) return null;
    // The receiver says what the television calls itself. Use it — "Woonkamer" is what the speaker
    // list should read; an address is what you fall back to, not what you show.
    try {
      final name = (jsonDecode(body) as Map)['name'];
      if (name is String && name.trim().isNotEmpty) return name.trim();
    } catch (_) {/* not JSON we understand; the address still identifies it */}
    return 'Shield ($host)';
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
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
  ///
  /// EVERY /24 this machine is on, not just the first. A PC with a Hyper-V switch, a VPN adapter or
  /// two network cards has several, and [primaryLanAddress] can only guess which one the television
  /// is on — guess wrong and the sweep runs to completion against a subnet with nothing in it, then
  /// reports no Shield with as much confidence as if it had looked in the right place.
  Future<List<ShieldTarget>> _findShields() async {
    final own = await lanAddresses();
    if (own.isEmpty) return [];
    final mine = own.toSet();
    final prefixes = sweepPrefixes(own);
    final found = <ShieldTarget>[];
    await Future.wait([
      for (final prefix in prefixes)
        for (var i = 1; i < 255; i++)
          () async {
            final host = '$prefix.$i';
            if (mine.contains(host)) return;
            final name = await _pingShield(host);
            if (name != null) found.add(ShieldTarget(host: host, name: name));
          }()
    ]);
    found.sort((a, b) => a.host.compareTo(b.host));
    return found;
  }

  Future<String?> _pingShield(String host) => probeShield(host);

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

    // Stamped BEFORE the SOAP calls, not after. Opening a track is three round trips of up to eight
    // seconds each, and until this line ran the timestamp still described the PREVIOUS track — so
    // the five-second tick arriving mid-open found the grace period long expired, asked a renderer
    // that had not started yet, was told STOPPED, and advanced again. The track being opened was
    // skipped without a sound. It is set again after the calls land, so the grace period is measured
    // from when the speaker actually got the track.
    session.startedAt = DateTime.now();

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
    session.currentUrl = url;
    session.nextUrl = null;

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
      // Bewaard, want dit is precies de URL die de speaker straks zelf gaat spelen zonder het te
      // melden. Hem terugzien in TrackURI is het enige signaal dat de overgang heeft plaatsgevonden.
      session.nextUrl = nextUrl;
    }
  }

  /// Is de speaker zelf doorgeschoven naar het nummer dat we hem alvast meegaven?
  ///
  /// De naadloze overgang van SetNextAVTransportURI is onzichtbaar in de transportstatus: PLAYING
  /// blijft PLAYING. Wat wél verandert is TrackURI. Zodra die gelijk is aan de URL die we als "volgende"
  /// hebben doorgegeven, weten we dat de speaker een nummer verder is en verhogen we de index -- en
  /// geven we meteen het nummer daarna mee, zodat de keten niet na twee liedjes ophoudt.
  ///
  /// Dit vervangt de STOPPED-weg niet: een speaker die de volgende-URL niet ondersteunt stopt wél, en
  /// dan is [_maybeAdvance] nog steeds wat de wachtrij doorzet.
  Future<bool> _followedRenderer(String? trackUri) async {
    final session = _session;
    if (session == null || trackUri == null) return false;
    final volgende = session.nextUrl;
    if (volgende == null || trackUri != volgende) return false;
    if (session.index + 1 >= session.queue.length) return false;
    session.index++;
    session.startedAt = DateTime.now();
    session.currentUrl = volgende;
    session.nextUrl = null;
    // Alleen de VOLGENDE doorgeven, niet opnieuw openen: de speaker speelt dit nummer al, en er
    // opnieuw een URL op zetten zou hem vanaf nul laten beginnen.
    final nextId = session.queue.elementAtOrNull(session.index + 1);
    final nextTrack = nextId == null ? null : catalog.track(nextId);
    if (nextId != null && nextTrack != null) {
      try {
        final nextUrl =
            await _streamUrlFor(nextId, nextTrack.ext, session.renderer, nextTrack.sampleRate);
        await _upnp.setNextUrl(
          session.renderer,
          nextUrl,
          title: nextTrack.title,
          artist: nextTrack.artist,
          album: nextTrack.album,
          mime: mimeForExt(nextTrack.ext),
        );
        session.nextUrl = nextUrl;
      } catch (_) {/* dan stopt de speaker na dit nummer en pakt _maybeAdvance het op */}
    }
    return true;
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

  /// True while an advance is in flight, so the five-second tick cannot start a second one.
  ///
  /// Every step of an advance is slow — one state query plus three more round trips to open the next
  /// track, each allowed eight seconds — and the timer kept firing straight through it. Two overlapping
  /// advances each move the index, so the queue walks forward faster than the speaker plays it.
  bool _advancing = false;

  /// Move to the next track once the speaker says it has finished.
  Future<void> _maybeAdvance() async {
    if (_advancing) return;
    final session = _session;
    if (session == null) return;
    // Give the renderer a moment after a start before believing "STOPPED" — a Sonos reports
    // exactly that for a second or two while it fetches the first bytes.
    if (DateTime.now().difference(session.startedAt) < const Duration(seconds: 8)) return;

    _advancing = true;
    try {
      // Eerst: is de speaker zelf al doorgeschoven? Dan is er niets te doen behalve bijhouden waar hij
      // is. Deze vraag gaat vóór de transportstatus, want in dat geval staat die nog op PLAYING en zou
      // de rest van deze functie niets doen terwijl de index achterloopt.
      final pos = await _upnp.positionInfo(session.renderer).catchError((_) => null);
      if (await _followedRenderer(pos?.trackUri)) return;

      final state = await _upnp.transportState(session.renderer);
      if (state == null || !state.isStopped) return;
      if (session.index + 1 >= session.queue.length) {
        _advance?.cancel();
        _session = null;
        return;
      }
      session.index++;
      try {
        await _openCurrent();
      } catch (e) {
        // The index had already moved, and the timer throws the error away — so a renderer that
        // refuses the track (a busy Sonos answers "Transition not available" with an HTTP 500) lost
        // that song silently and the next tick took the one after it. Put the queue back where it
        // was and let the next tick try the same track again.
        session.index--;
        session.startedAt = DateTime.now();
        debugPrint('cast: kon ${session.queue.elementAtOrNull(session.index + 1)} niet openen: $e');
      }
    } finally {
      _advancing = false;
    }
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
      case 'seek':
        // Seconds on the wire rather than a formatted time: the phone has a slider, not a clock,
        // and the H:MM:SS the renderer wants is upnp.dart's business.
        await _upnp.seek(renderer, Duration(seconds: value ?? 0));
      default:
        throw ArgumentError('unknown action: $action');
    }
  }

  /// What the speaker is doing, for a device that is holding the remote.
  ///
  /// Everything here is asked of the SPEAKER. A phone that is only steering does not decode the
  /// audio and cannot know the position; the alternative was a bar that crawled along on a guess,
  /// which is a lie you can sit and watch.
  ///
  /// Every field is optional on purpose. A renderer that answers some questions and not others is
  /// ordinary, and "no volume" must not cost you the play button.
  /// [withVolume] because this is polled while a bar moves on screen, and an embedded UPnP stack is
  /// not a web server. Volume almost never changes on its own, so asking for it every two seconds
  /// is a third more traffic to the speaker for an answer that is nearly always the same one.
  Future<Map<String, dynamic>> status(String deviceId, {bool withVolume = false}) async {
    final out = <String, dynamic>{'casting': false};
    // A Shield runs our own receiver and reports through the shared state, not through UPnP.
    if (_shields.any((s) => s.id == deviceId)) return out;

    final Renderer renderer;
    try {
      renderer = await _renderer(deviceId);
    } catch (_) {
      return out; // gone from the network; the caller shows its own last known state
    }
    final session = _session;
    out['casting'] = session != null && session.renderer.id == renderer.id;
    if (session != null) {
      out['index'] = session.index;
      out['queueLength'] = session.queue.length;
      out['trackId'] = session.queue.elementAtOrNull(session.index);
    }
    // Asked in parallel: three round trips to an embedded stack, one after the other, is most of a
    // second — and this is polled while someone watches a progress bar.
    final results = await Future.wait([
      _upnp.positionInfo(renderer).catchError((_) => null),
      _upnp.transportState(renderer).catchError((_) => null),
      if (withVolume) _upnp.getVolume(renderer).catchError((_) => null),
    ]);
    final pos = results[0] as ({Duration position, Duration duration})?;
    final state = results[1] as TransportState?;
    final volume = withVolume ? results[2] as int? : null;
    if (pos != null) {
      out['positionMs'] = pos.position.inMilliseconds;
      out['durationMs'] = pos.duration.inMilliseconds;
    }
    if (state != null) out['playing'] = state.isPlaying;
    if (volume != null) out['volume'] = volume;
    return out;
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

  /// De URL's die deze speaker gekregen heeft voor het huidige en het volgende nummer.
  ///
  /// Nodig om te ZIEN dat de speaker zelf is doorgeschoven. De app geeft het volgende nummer alvast
  /// mee zodat er geen gat valt tussen twee liedjes, en dan gaat een Sonos van PLAYING naar PLAYING
  /// zonder ooit STOPPED te zeggen. Wie alleen op STOPPED let, loopt vanaf dat moment één nummer
  /// achter: de speaker speelt nummer 2, de app toont nummer 1, en "volgende" gaat naar het nummer dat
  /// al klinkt. Bij één album valt dat nauwelijks op, bij shuffle-all is elk nummer een ander album.
  String? currentUrl, nextUrl;
}

extension _ElementAtOrNull<E> on List<E> {
  E? elementAtOrNull(int index) => (index >= 0 && index < length) ? this[index] : null;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
