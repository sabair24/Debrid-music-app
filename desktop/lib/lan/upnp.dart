import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import 'net.dart';

/// A speaker on the network that can be told to play a URL.
class Renderer {
  const Renderer({
    required this.id,
    required this.name,
    required this.host,
    required this.avTransportUrl,
    this.renderingControlUrl,
    this.model = '',
    this.manufacturer = '',
  });

  final String id;
  final String name;
  final String host;
  final String avTransportUrl;
  final String? renderingControlUrl;
  final String model;
  final String manufacturer;

  /// Sonos plays FLAC and ALAC up to 24 bit, but only to 48 kHz — and it *skips* a file above
  /// that rather than downsampling it, so a hi-res album would go quiet track by track with no
  /// error anywhere. Knowing which speakers are Sonos is what lets the stream be converted
  /// before it is sent, instead of the music simply not playing.
  bool get isSonos => manufacturer.toLowerCase().contains('sonos');

  int get maxSampleRate => isSonos ? 48000 : 0; // 0 = no known ceiling

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'model': model,
        'manufacturer': manufacturer,
        'kind': isSonos ? 'sonos' : 'upnp',
        'maxSampleRate': maxSampleRate,
      };
}

/// Where a renderer is in a track — what the queue needs to know to advance.
class TransportState {
  const TransportState(this.state);
  final String state; // PLAYING, PAUSED_PLAYBACK, STOPPED, TRANSITIONING, NO_MEDIA_PRESENT

  bool get isStopped => state == 'STOPPED' || state == 'NO_MEDIA_PRESENT';
  bool get isPlaying => state == 'PLAYING';
}

/// A minimal UPnP control point: finds MediaRenderers over SSDP and drives them with SOAP.
///
/// Ported from the Kotlin server's `cast/UpnpCast.kt`, which was written against these same two
/// Sonos speakers. Plain UPnP, so it speaks to a Sonos and to the KEF alike — no vendor SDK, no
/// cloud account, and nothing that stops working when a manufacturer changes their API.
class UpnpControlPoint {
  static const _ssdpAddress = '239.255.255.250';
  static const _ssdpPort = 1900;

  static const _searchTargets = [
    'urn:schemas-upnp-org:device:MediaRenderer:1',
    'urn:schemas-upnp-org:device:ZonePlayer:1', // Sonos answers to this one
  ];

  /// Broadcast an M-SEARCH and describe whatever answers.
  ///
  /// One socket per network card, not one bound to 0.0.0.0. A multicast datagram sent from the
  /// wildcard address leaves by whichever single interface the routing table prefers, and on a
  /// Windows PC that is very often not the one the speakers are on — a Hyper-V switch, a VPN
  /// adapter or the second of two network cards will happily win. The search then goes out on a
  /// network with nothing on it, and a Sonos that is plugged in and playing simply never appears.
  ///
  /// Asking on every card costs one extra socket each and removes the guess entirely.
  Future<List<Renderer>> discover({Duration timeout = const Duration(seconds: 3)}) async {
    final locations = <String>{};
    final sockets = <RawDatagramSocket>[];
    final group = InternetAddress(_ssdpAddress);

    void collect(RawDatagramSocket s) {
      s.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = s.receive();
        if (packet == null) return;
        final text = utf8.decode(packet.data, allowMalformed: true);
        for (final line in const LineSplitter().convert(text)) {
          if (line.toLowerCase().startsWith('location:')) {
            locations.add(line.substring(9).trim());
          }
        }
      });
    }

    for (final address in await lanAddresses()) {
      try {
        final s = await RawDatagramSocket.bind(InternetAddress(address), 0);
        s.multicastHops = 2;
        collect(s);
        sockets.add(s);
      } on SocketException catch (e) {
        // One card refusing to bind is not a reason to search on none of them.
        debugPrint('SSDP: cannot search from $address: ${e.message}');
      }
    }

    // A machine with no usable card of its own still gets one try the old way.
    if (sockets.isEmpty) {
      try {
        final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)..multicastHops = 2;
        collect(s);
        sockets.add(s);
      } on SocketException catch (e) {
        debugPrint('SSDP discovery failed: ${e.message}');
      }
    }

    if (sockets.isNotEmpty) {
      for (final target in _searchTargets) {
        final message = 'M-SEARCH * HTTP/1.1\r\n'
            'HOST: $_ssdpAddress:$_ssdpPort\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 2\r\n'
            'ST: $target\r\n\r\n';
        // Twice: SSDP is UDP, and a single lost packet means a speaker silently doesn't appear.
        for (var i = 0; i < 2; i++) {
          for (final s in sockets) {
            try {
              s.send(utf8.encode(message), group, _ssdpPort);
            } catch (_) {/* that card is not going to answer; the others still might */}
          }
        }
      }
      await Future<void>.delayed(timeout);
    }
    for (final s in sockets) {
      s.close();
    }

    final byHost = <String, Renderer>{};
    await Future.wait(locations.map((location) async {
      final renderer = await _describe(location);
      // Keyed by host: a Sonos answers both search targets, and the KEF advertises more than one
      // device document. Without this the picker shows the same speaker several times.
      if (renderer != null) byHost.putIfAbsent(renderer.host, () => renderer);
    }));
    return byHost.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Fetch a device description and pull out what we need to drive it.
  Future<Renderer?> _describe(String location) async {
    final xml = await _httpGet(location);
    if (xml == null) return null;
    try {
      final document = XmlDocument.parse(xml);
      final uri = Uri.parse(location);
      final base = document.findAllElements('URLBase').firstOrNull?.innerText.trim();
      final root = (base != null && base.isNotEmpty)
          ? base
          : '${uri.scheme}://${uri.host}:${uri.port}';

      String? avTransport;
      String? renderingControl;
      for (final service in document.findAllElements('service')) {
        final type = service.findElements('serviceType').firstOrNull?.innerText ?? '';
        final control = service.findElements('controlURL').firstOrNull?.innerText.trim() ?? '';
        if (control.isEmpty) continue;
        final absolute = control.startsWith('http')
            ? control
            : '${root.replaceAll(RegExp(r'/+$'), '')}/${control.replaceAll(RegExp(r'^/+'), '')}';
        // Match the service name EXACTLY, not by substring. A Sonos exposes both
        // `RenderingControl` and `GroupRenderingControl`, and a `contains` check lets the group
        // service overwrite the real one — after which GetVolume comes back "401 Invalid
        // Action", which reads like a permissions problem and is nothing of the sort.
        switch (_serviceName(type)) {
          case 'AVTransport':
            avTransport = absolute;
          case 'RenderingControl':
            renderingControl = absolute;
        }
      }
      // No AVTransport, nothing to play on. This is what keeps a Philips Hue bridge — which
      // answers SSDP perfectly happily — out of a list of speakers.
      if (avTransport == null) return null;

      final rawName = document.findAllElements('friendlyName').firstOrNull?.innerText.trim() ?? uri.host;
      return Renderer(
        id: uri.host,
        name: _tidyName(rawName),
        host: uri.host,
        avTransportUrl: avTransport,
        renderingControlUrl: renderingControl,
        model: document.findAllElements('modelName').firstOrNull?.innerText.trim() ?? '',
        manufacturer: document.findAllElements('manufacturer').firstOrNull?.innerText.trim() ?? '',
      );
    } catch (e) {
      debugPrint('could not read $location: $e');
      return null;
    }
  }

  /// `urn:schemas-upnp-org:service:RenderingControl:1` → `RenderingControl`.
  static String _serviceName(String serviceType) {
    final parts = serviceType.split(':');
    return parts.length >= 2 ? parts[parts.length - 2] : serviceType;
  }

  @visibleForTesting
  static String serviceNameForTest(String serviceType) => _serviceName(serviceType);

  /// Sonos names itself "192.168.0.188 - Sonos Move - RINCON_F0F6…". Keep the middle.
  @visibleForTesting
  static String tidyNameForTest(String raw) => _tidyName(raw);

  @visibleForTesting
  static String didlForTest(
    String url, {
    required String title,
    required String artist,
    required String album,
    required String mime,
    String? artUrl,
  }) =>
      _didl(url, title: title, artist: artist, album: album, mime: mime, artUrl: artUrl);

  static String _tidyName(String raw) {
    final trimmed = raw
        .replaceFirst(RegExp(r'^\d+\.\d+\.\d+\.\d+\s*-\s*'), '')
        .replaceFirst(RegExp(r'\s*-\s*RINCON_\w+$'), '')
        .trim();
    return trimmed.isEmpty ? raw : trimmed;
  }

  // ── Transport ────────────────────────────────────────────────────────────

  Future<void> playUrl(
    Renderer renderer,
    String url, {
    required String title,
    required String artist,
    required String album,
    required String mime,
    String? artUrl,
  }) async {
    final metadata = _didl(url, title: title, artist: artist, album: album, mime: mime, artUrl: artUrl);
    await _soap(renderer.avTransportUrl, 'AVTransport', 'SetAVTransportURI',
        '<InstanceID>0</InstanceID><CurrentURI>${_escape(url)}</CurrentURI>'
        '<CurrentURIMetaData>${_escape(metadata)}</CurrentURIMetaData>');
    await _soap(renderer.avTransportUrl, 'AVTransport', 'Play',
        '<InstanceID>0</InstanceID><Speed>1</Speed>');
  }

  /// Queue the next track so the gap between songs is the renderer's, not ours.
  Future<void> setNextUrl(
    Renderer renderer,
    String url, {
    required String title,
    required String artist,
    required String album,
    required String mime,
    String? artUrl,
  }) async {
    final metadata = _didl(url, title: title, artist: artist, album: album, mime: mime, artUrl: artUrl);
    await _soap(renderer.avTransportUrl, 'AVTransport', 'SetNextAVTransportURI',
        '<InstanceID>0</InstanceID><NextURI>${_escape(url)}</NextURI>'
        '<NextURIMetaData>${_escape(metadata)}</NextURIMetaData>');
  }

  Future<void> play(Renderer r) =>
      _soap(r.avTransportUrl, 'AVTransport', 'Play', '<InstanceID>0</InstanceID><Speed>1</Speed>');

  Future<void> pause(Renderer r) =>
      _soap(r.avTransportUrl, 'AVTransport', 'Pause', '<InstanceID>0</InstanceID>');

  Future<void> stop(Renderer r) =>
      _soap(r.avTransportUrl, 'AVTransport', 'Stop', '<InstanceID>0</InstanceID>');

  Future<void> setVolume(Renderer r, int volume) async {
    final url = r.renderingControlUrl;
    if (url == null) return;
    await _soap(url, 'RenderingControl', 'SetVolume',
        '<InstanceID>0</InstanceID><Channel>Master</Channel>'
        '<DesiredVolume>${volume.clamp(0, 100)}</DesiredVolume>');
  }

  Future<int?> getVolume(Renderer r) async {
    final url = r.renderingControlUrl;
    if (url == null) return null;
    final body = await _soap(url, 'RenderingControl', 'GetVolume',
        '<InstanceID>0</InstanceID><Channel>Master</Channel>');
    final match = RegExp(r'<CurrentVolume>(\d+)</CurrentVolume>').firstMatch(body ?? '');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// What the speaker is doing — used to notice a track ended and send the next one.
  Future<TransportState?> transportState(Renderer r) async {
    final body = await _soap(r.avTransportUrl, 'AVTransport', 'GetTransportInfo',
        '<InstanceID>0</InstanceID>');
    final match = RegExp(r'<CurrentTransportState>(\w+)</CurrentTransportState>').firstMatch(body ?? '');
    return match == null ? null : TransportState(match.group(1)!);
  }

  // ── plumbing ─────────────────────────────────────────────────────────────

  Future<String?> _soap(String controlUrl, String service, String action, String arguments) async {
    final serviceType = 'urn:schemas-upnp-org:service:$service:1';
    final envelope = '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body><u:$action xmlns:u="$serviceType">$arguments</u:$action></s:Body></s:Envelope>';

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.postUrl(Uri.parse(controlUrl));
      final bytes = utf8.encode(envelope);
      request.headers
        ..set(HttpHeaders.contentTypeHeader, 'text/xml; charset="utf-8"')
        ..set('SOAPACTION', '"$serviceType#$action"');
      // Content-Length, explicitly. Without it Dart sends the body chunked, and an embedded UPnP
      // stack — Sonos included — simply waits for a length that never comes: the call hangs
      // until it times out, with no error from either side. The same request via curl, which
      // sets a length, returns in 20 ms.
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(const Duration(seconds: 8));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('SOAP $action -> ${response.statusCode}: ${body.substring(0, body.length.clamp(0, 300))}');
        throw HttpException('Speaker refused $action (HTTP ${response.statusCode})');
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _httpGet(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(const Duration(seconds: 5));
      return await response.transform(utf8.decoder).join();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// The track's details, in the form a renderer expects.
  ///
  /// Not decoration: without DIDL a Sonos plays the audio but shows "—" where the title, artist
  /// and sleeve should be, on the speaker and in the Sonos app.
  static String _didl(
    String url, {
    required String title,
    required String artist,
    required String album,
    required String mime,
    String? artUrl,
  }) =>
      '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
      '<item id="dm-0" parentID="-1" restricted="1">'
      '<dc:title>${_escape(title)}</dc:title>'
      '<dc:creator>${_escape(artist)}</dc:creator>'
      '<upnp:artist>${_escape(artist)}</upnp:artist>'
      '<upnp:album>${_escape(album)}</upnp:album>'
      '${artUrl == null ? '' : '<upnp:albumArtURI>${_escape(artUrl)}</upnp:albumArtURI>'}'
      '<upnp:class>object.item.audioItem.musicTrack</upnp:class>'
      '<res protocolInfo="http-get:*:$mime:*">${_escape(url)}</res>'
      '</item></DIDL-Lite>';

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
